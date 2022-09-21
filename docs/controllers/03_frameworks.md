## Introduction To Kubernetes Controller Frameworks

### Before You Continue

It is **required** that you read the section on [Introduction To Informers](./02_informers.md) before reading this section. 

It is also **highly recommended** that you read the section on [Introduction to Kubernetes Clients](./01_clients.md), specifically the sections on the [Anatomy of a Kubernetes Resources](./01_clients.md#the-anatomy-of-a-kubernetes-resource) and [How `kubectl` translates Requests to HTTP API calls](./01_clients.md#special-topic-how-does-kubectl-translate-requests-to-http-api-calls).

### A Brief Recap

The Informer pattern is a pattern for a piece of software that is "informed" of changes that happen to a **single type** of Kubernetes resource (i.e. a `Deployment` or a `Job`).

In practice, we want the `Informer` to do two things on being "informed" of a change:
1. **Store the "current state of the world" in-memory**
2. **Trigger an action on "processing" a change to a resource (Reconciliation)**

To accomplish this, the [`cache.SharedIndexInformer`](https://pkg.go.dev/k8s.io/client-go/tools/cache#NewSharedIndexInformer) construct from the [k8s.io/client-go/tools/cache](https://pkg.go.dev/k8s.io/client-go/tools/cache) library can be used, which can be diagramtically understood as having the following architecture:

![Client-Go Controller Diagram](../images/client-go-controller-interaction.jpg)

As discussed in the previous section, you can follow this diagram with the following construct:
1. A Kubernetes Client, which offers the ability to `List` and `Watch` is converted into a [`cache.ListerWatcher`](https://pkg.go.dev/k8s.io/client-go/tools/cache#ListerWatcher) interface, which allows it to list all Kubernetes resource of a given type from the Kubernetes API Server and watch for changes.
2. An in-memory [`cache.DeltaFIFO`](https://pkg.go.dev/k8s.io/client-go/tools/cache#DeltaFIFO), which is a type that satisfies the [`cache.Queue`](https://pkg.go.dev/k8s.io/client-go/tools/cache#Queue) interface, which in turn satisfies the more generic [`cache.Store`](https://pkg.go.dev/k8s.io/client-go/tools/cache#Store) interface, is combined with our `cache.ListerWatcher` to form the [`cache.Reflector`](https://pkg.go.dev/k8s.io/client-go/tools/cache#Reflector). On starting the `cache.Reflector`, the Kubernetes Watch Events receieved by our `cache.ListerWatcher` is automatically populated in the `cache.DeltaFIFO`.
3. Leveraging the fact that our `cache.DeltaFIFO` is a `cache.Queue`, the [`cache.Controller`](https://pkg.go.dev/k8s.io/client-go/tools/cache#Controller) dynamically creates the `cache.Reflector` we defined in the second step to automatically call `cache.Queue.Pop(PopProcessFunc)` on a regular interval (the `resync interval`), which forms the basis for an **auto-populating and auto-processing `cache.Queue` of Kubernetes resource deltas**.
4. On popping an element off the queue in a regular interval, the `cache.Controller` we defined above is combined with two other constructs: the [`cache.ThreadSafeStore`](https://pkg.go.dev/k8s.io/client-go/tools/cache#ThreadSafeStore) and one or more [`cache.ResourceEventHandlers`](https://pkg.go.dev/k8s.io/client-go/tools/cache#ResourceEventHandler). This logically forms the [`cache.SharedIndexInformer`](https://pkg.go.dev/k8s.io/client-go/tools/cache#NewSharedIndexInformer), which covers everything in the diagram above up till the dotted horizontal line.
5. On first popping off the object from the `cache.DeltaFIFO`, the `cache.SharedIndexInformer` will store the updated Kubernetes resource (or delete it, if it has been removed) in the `cache.ThreadSafeStore`, by default using `<namespace>/<name>` as the key. 

> **Note:** If more indexers are added by calling `cache.SharedIndexInformer.AddIndexers(Indexers)` (where `Indexers` is a `map[string]func(obj interface{}) ([]string, error)`), each index will be calculated on entry into the cache at this step. This is why we add `cache.Indexers` before starting controllers.

> **Note:** This `cache.Store` is accessible by calling the `cache.SharedIndexInformer.GetStore()` function. If you need the [`cache.Indexer`](https://pkg.go.dev/k8s.io/client-go/tools/cache#Indexer)-specific capabilities as well, call `cache.SharedIndexInformer.GetIndexer()`.

6. After adding the object to our `cache.ThreadSafeStore`, every `ResourceEventHandler` registered with `cache.SharedIndexInformer.AddResourceEventHandler(ResourceEventHandler)` or `cache.SharedIndexInformer.AddResourceEventHandlerWithResyncPeriod(ResourceEventHandler, time.Duration)` will be called in order. **However, the `ResourceEventHandler` will only be called once per enqueue; if there is an error in handling of the ResourceEventHandler, it will be up to the ResourceEventHandler to seperately handle re-enqueue logic.**

> **Note:** This comes directly from the [`cache.SharedInfomer`](https://pkg.go.dev/k8s.io/client-go/tools/cache#SharedInformer) Go documentation in the following excerpt:
>
> A client must process each notification promptly; a SharedInformer is not engineered to deal well with a large backlog of notifications to deliver. Lengthy processing should be passed off to something else, for example through a `client-go/util/workqueue`.

In the next part, we will talk about how what is **below the dotted line and more**  by looking at two Controller Frameworks: [`rancher/lasso`](https://github.com/rancher/lasso) and [`rancher/wrangler`](https://github.com/rancher/wrangler).

### Why Do We Need Controller Frameworks?

While the `cache.SharedIndexInformer` allows us to satisfy the definition of the `Informer` we listed above, generally Custom Controllers that are written for Kubernetes need the following additional features:

1. **Re-trigger the reconciliation process on handler errors and handle reconciliation in parallel**: as mentioned above, this is not suitable for the `cache.SharedIndexInformer` to handle, so this is generally achieved by leveraging the [`k8s.io/client-go/util/workqueue`](https://pkg.go.dev/k8s.io/client-go/util/workqueue) package. Generally, it's also assumed that handlers may have non-trivial logic for handling changes, so they should run on **multiple worker goroutines / threads in parallel**.

> **Note:** Examples of handler logic that might require non-sequential execution of handlers include, but are not limited to:
>
> - Requiring interaction with the Kubernetes API (i.e. `GitJobs` create `Jobs`)
> 
> - Requiring waiting and watching external processes for a certain amount of time (i.e. `HelmChart` creates and waits for a Helm install `Job` to finish)
> 
> - Requiring interaction with external APIs (i.e. `Cluster` creates and waits for external APIs like AWS or Vsphere to create underlying resources) that may have
>
> - etc.

2. **Manage creating Kubernetes clients and `cache.SharedIndexInformers` on multiple types of Kubernetes resources in an resource efficient manner**: generally this will involve creating constructs like a `Shared*Factory` that will ensure that there's only one copy of a given client or informer that is given to all parts of your code that need it. 

> **Note:** This is also where the [`runtime.Scheme`](https://pkg.go.dev/k8s.io/client-go/pkg/runtime#Scheme), a construct which helps map Go types to GVKs and vice-versa, comes into play. More on this [later](#the-runtimeschemehttpspkggodevgopkginkubernetesclient-gov2pkgruntimescheme).

3. **Generate code to make it easier to define custom types and controllers**: as listed on the section on the [Anatomy of a Kubernetes Resources](./01_clients.md#the-anatomy-of-a-kubernetes-resource), any custom type that is supposed to represent a Kubernetes resource needs to implement certain functions to be considered a Kubernetes resource, such as `GetObjectKind()` or `DeepCopyObject()` (which satisfies the `runtime.Object` interface). It should also be added to the Controller Framework's default `runtime.Scheme` to be used in `Shared*Factory` constructs. This is generally handled by code generation via `go generate` commands, which will create additional **typed** functions, eliminating the need for developers to type cast objects received by generic Handler functions.

4. **Define helper code to encapsulte common controller design patterns**: these include special types of handlers such as `Register*StatusHandler`, `Register*GeneratingHandler`, `relatedresource.Watch` that simplify the logic necessary to be written on a controller **if it falls under a specific controller design pattern**.

In the next part, we will talk about how the first two features are implemented by [`rancher/lasso`](https://github.com/rancher/lasso).

In the following part, we will talk about how the second two features and more are implemented by [`rancher/wrangler`](https://github.com/rancher/wrangler).

### [Lasso](https://github.com/rancher/lasso)

We will now look into our first lower-level Controller Framework: [Lasso](https://github.com/rancher/lasso)!

> **Note:** This is roughly equivalent to the open-source [kubernetes-sigs/controller-runtime](https://github.com/kubernetes-sigs/controller-runtime) framework, but [Lasso](https://github.com/rancher/lasso) was created a long time before the `controller-runtime` framework ever existed.

As mentioned above, there are two features that we look for our lower-level Controller Framework to help us additionally implement:

1. **Re-trigger the reconciliation process on handler errors and handle reconciliation in parallel**

2. **Manage creating Kubernetes clients and `cache.SharedIndexInformers` on multiple types of Kubernetes resources in an resource efficient manner**

In addition to these features, [Lasso](https://github.com/rancher/lasso) additionally provides the following features:

1. **Lazy / "Deferred" Execution Or Automatic "Retry" logic**: In most areas of the Lasso code, you will see simple `deferred*` wrappers, such as `deferredCache` and `deferredListerWatcher`, which only execute initialization actions on the underlying interfaces on the first time a resource is required to be initialized (i.e. the first time a controller is registered). You will also see `retry*` wrappers, such as `retryMapper`, which execute continously retry requests until a successful execution. We will not discuss these constructs in detail, but it should be noted that such constructs are added for performance optimization and code simplification, respectively.

> **Important Note**: As you will see in the section below, Lasso tends to use fairly confusing nomenclature for internal components, such as referring to what we previously described as a `cache.SharedIndexInformer` as a `Cache`; this is partially due to the fact that it was designed alongside Kubernetes's own development, which meant these names were not standard at the time of its creation. So it's probably a good idea to throw your dictionary of words out of the window for this section and just follow along!

### `NewClient` from [`pkg/client`](https://github.com/rancher/lasso/blob/master/pkg/client)

If you recall the previous section that went over [how `kubectl` translates requests To HTTP API calls](./01_clients.md#special-topic-how-does-kubectl-translate-requests-to-http-api-calls), the `k8s.io/client-go/rest` package provides the ability to create a [`rest.RESTClient`](https://pkg.go.dev/k8s.io/client-go/rest#RESTClient) from a `KUBECONFIG` file, which implements the [`rest.Interface`](https://pkg.go.dev/k8s.io/client-go/rest#Interface).

Using this as the underlying implementation, Lasso's `NewClient` function simply creates a wrapper on this interface to define a `Client` that can be used to interact with the Kubernetes API:

```go
func NewClient(gvr schema.GroupVersionResource, kind string, namespaced bool, client rest.Interface, defaultTimeout time.Duration) *Client

func (c *Client) Get(ctx context.Context, namespace, name string, result runtime.Object, options metav1.GetOptions) error
func (c *Client) List(ctx context.Context, namespace string, result runtime.Object, opts metav1.ListOptions) error
func (c *Client) Watch(ctx context.Context, namespace string, opts metav1.ListOptions) (watch.Interface, error)
func (c *Client) Create(ctx context.Context, namespace string, obj, result runtime.Object, opts metav1.CreateOptions) error
func (c *Client) Update(ctx context.Context, namespace string, obj, result runtime.Object, opts metav1.UpdateOptions) error
func (c *Client) UpdateStatus(ctx context.Context, namespace string, obj, result runtime.Object, opts metav1.UpdateOptions) error
func (c *Client) Delete(ctx context.Context, namespace, name string, opts metav1.DeleteOptions) error
func (c *Client) DeleteCollection(ctx context.Context, namespace string, opts metav1.DeleteOptions, listOpts metav1.ListOptions) error
func (c *Client) Patch(ctx context.Context, namespace, name string, pt types.PatchType, data []byte, result runtime.Object, opts metav1.PatchOptions, subresources ...string) error
```

While this client is generally defined in order to allow us to create a `NewCache` (i.e. a `cache.SharedIndexInformer`, as defined in the next part) off the fact that it implements `List` and `Watch` (therefore trivially being wrapped in the `cache.ListerWatcher` interface that is needed to create a `cache.SharedIndexInformer`), it is also generally offered by Lasso Controllers to allow a user to communicate with the Kubernetes API Server to get the latest, up-to-date state of resources, without referencing the local cache in-memory or perform operations (such as when you need a `GitJob` CR to create a `Job` as part of its handling).

> **Note:** For now, we will move on to the `pkg/cache` module; however, we will revisit this package later when we talk about the `SharedClientFactory`.

### `NewCache` from [`pkg/cache`](https://github.com/rancher/lasso/blob/master/pkg/cache)

Now that we have a `Client` that can serve as our `cache.ListerWatcher`, we're ready to create our `cache.SharedIndexInformer`!

Confusingly enough, [Lasso](https://github.com/rancher/lasso) allows you to create the underlying `cache.SharedIndexInformer` we described above with the following command:

```go
NewCache(obj, listObj runtime.Object, client *client.Client, opts *Options) cache.SharedIndexInformer
```

On initializing this cache, it returns `cache.SharedIndexInformer` that utilizes a `deferredListerWatcher` (see the note in the section above; this is just a normal `cache.ListerWatcher` that is deferred on initialization), which is wrapped in a `deferredCache`.

But for practical purposes, we can just think of this as the normal `cache.SharedIndexInformer` that we got familiar with [in the previous section](./02_informers.md#what-is-a-sharedindexinformer).

> **Note:** For now, we will move on to the `pkg/controller` module; however, we will revisit this package later when we talk about the `SharedCacheFactory` (also confusingly and erroneously defined in a file called `pkg/cache/sharedinformerfactory.go`).

### `New` from [`pkg/controller`]((https://github.com/rancher/lasso/blob/master/pkg/controller))

The `New` function in the `pkg/controller` module is the entrypoint for understanding how [Lasso](https://github.com/rancher/lasso) works to solve the first feature that our Controller Framework needs to implement. 

As a reminder, what we would like Lasso to implement for this feature is everything below the dotted line in this diagram; specifically the **parallel execution** of handlers and **re-enqueue on errors**:

![Client-Go Controller Diagram](../images/client-go-controller-interaction.jpg)

On calling the `New` function, we see that the following logic is executed, which generally utilizes our `cache.SharedIndexInformer` created from the `NewCache` function above:

```go
func New(name string, informer cache.SharedIndexInformer, startCache func(context.Context) error, handler Handler, opts *Options) Controller {
	opts = applyDefaultOptions(opts)

	controller := &controller{
		name:        name,
		handler:     handler,
		informer:    informer,
		rateLimiter: opts.RateLimiter,
		startCache:  startCache,
	}

	informer.AddEventHandler(cache.ResourceEventHandlerFuncs{
		AddFunc: controller.handleObject,
		UpdateFunc: func(old, new interface{}) {
			if !opts.SyncOnlyChangedObjects || old.(ResourceVersionGetter).GetResourceVersion() != new.(ResourceVersionGetter).GetResourceVersion() {
				// If syncOnlyChangedObjects is disabled, objects will be handled regardless of whether an update actually took place.
				// Otherwise, objects will only be handled if they have changed
				controller.handleObject(new)
			}
		},
		DeleteFunc: controller.handleObject,
	})

	return controller
}
```

As seen in the Go code embedded above, we simply take in the `cache.SharedIndexInformer` and add a **single** `EventHandler` that calls the `handleObject` function on **any operation** that occurs to a Kubernetes resource that our informer watches for. We also take in a `Handler`, which is generically defined as follows:

```go
type Handler interface {
	OnChange(key string, obj runtime.Object) error
}
```

> **Note:** Why don't we have different `handleObject` functions for different types of operations and why does the `Handler` only support `OnChange` operations?
>
> In the Lasso controller world (and generically in the Kubernetes controller world), handlers that are defined are expected to operate in a **declarative** way: that is, they should not be concerned with **how** a resource ended up in the state that it is in, but rather only be concerned about **what** state the resource is currently in to determine what should happen next.
>
> The expectation here is that even if a handler results in the resource itself being modified (i.e. updating the `status` of a resource according to the `spec` fields), it should be **eventually consistent** with a desired definition of a resource.
>
> Therefore, it is bad practice in controllers to do something such as adding a timestamp for when a resource was handled on the resource itself, since that will never be consistent (as adding the timestamp triggers a change, which retriggers the controller, and goes through an infinite loop).
>
> Understanding this declarative nature of controller handlers is one of the hardest parts of designing controller handlers but is the heart of Kubernetes's reconciliation model for controllers.
>
> This is also why Kubernetes controllers are often described as following a Level Triggered system design; if you would like to dig into the technicalities, please read [this article on Level Triggering and Reconciliation in Kubernetes](https://medium.com/hackernoon/level-triggering-and-reconciliation-in-kubernetes-1f17fe30333d).

And when we look at the `handleObject` function, we see that all it really does is handle some edge cases and call `enqueue` in turn, which will either add the enqueued object to a list of `[]startKey` (which is just a list of `<namespace>/<name>` strings that gets called on first `Run`ning the controller) or directly add it to `c.workqueue`:

```go
func (c *controller) handleObject(obj interface{}) {
	if _, ok := obj.(metav1.Object); !ok {
		tombstone, ok := obj.(cache.DeletedFinalStateUnknown)
		if !ok {
			log.Errorf("error decoding object, invalid type")
			return
		}
		newObj, ok := tombstone.Obj.(metav1.Object)
		if !ok {
			log.Errorf("error decoding object tombstone, invalid type")
			return
		}
		obj = newObj
	}
	c.enqueue(obj)
}

func (c *controller) enqueue(obj interface{}) {
	var key string
	var err error
	if key, err = cache.MetaNamespaceKeyFunc(obj); err != nil {
		log.Errorf("%v", err)
		return
	}
	c.startLock.Lock()
	if c.workqueue == nil {
		c.startKeys = append(c.startKeys, startKey{key: key})
	} else {
		c.workqueue.Add(key)
	}
	c.startLock.Unlock()
}
```

As described [at the start of this section](#lassohttpsgithubcomrancherlasso), we will skip over discussing `startKeys` since that falls under `Lazy / "Deferred" Execution Or Automatic "Retry" logic` that optimizes the way that controllers are started. 

Instead, we will just look at what happens on an `enqueue` call when a controller has already started, which is a great way to introduce the [`k8s.io/client-go/util/workqueue`](https://pkg.go.dev/k8s.io/client-go/util/workqueue).

#### The [`k8s.io/client-go/util/workqueue`](https://pkg.go.dev/k8s.io/client-go/util/workqueue)

On calling `Start` on the our controller, we instantiate and populate (with the `startKeys` referenced above) a `workqueue.DelayingInterface` with the following call:

```go
c.workqueue = workqueue.NewNamedRateLimitingQueue(c.rateLimiter, c.name)
```

This effectively gives us a [`workqueue.DelayingInterface`](https://pkg.go.dev/k8s.io/client-go/util/workqueue#DelayingInterface), which is a type of [`workqueue.Interface`](https://pkg.go.dev/k8s.io/client-go/util/workqueue#Interface) that implements the following functions:

```go
type DelayingInterface interface {
	Interface
	// AddAfter adds an item to the workqueue after the indicated duration has passed
	AddAfter(item interface{}, duration time.Duration)
}

type Interface interface {
	Add(item interface{})
	Len() int
	Get() (item interface{}, shutdown bool)
	Done(item interface{})
	ShutDown()
	ShutDownWithDrain()
	ShuttingDown() bool
}
```

While we won't go through the specific details of the implementation, effectively the `workqueue.Interface` offers us something that adheres to the following guarantees, as described at the top of the Go documentation for the package:

> Package workqueue provides a simple queue that supports the following features:
> 
> - Fair: items processed in the order in which they are added.
>
> - Stingy: a single item will not be processed multiple times concurrently, and if an item is added multiple times before it can be processed, it will only be processed once.
>
> - Multiple consumers and producers. In particular, it is allowed for an item to be reenqueued while it is being processed.
>
> - Shutdown notifications.

These guarentees, especially the first two, are exactly what we need in order to define **parallel execution** of handlers with the ability to **re-enqueue errors**.

Specifically:
- The `Fair` guarantee ensures that we execute on changes that we see from the Kubernetes API server in order.
- The `Stingy` guarantee ensures that when a worker thread pulls an item (normally a string in the format `<namespace/name>`) off the workqueue, it is **the only one that is allowed to be working on that specific item** until the `Done(item)` operation is called on the resource. Till then, other worker threads will only receive other items, which is exactly what we want to happen.
- The `Multiple consumers and producers` guarantee allows us to re-enqueue an item while it is being processed; for example, if the resource changes while your controller is trying to handle it.
- The `Shutdown notifications` guarantee allows us to stop controllers if required. This can be used to gracefully shutdown controllers to finish processing before exit.

#### Coming Back Full Circle

With the guarentees of the [`workqueue.DelayingInterface`](https://pkg.go.dev/k8s.io/client-go/util/workqueue#DelayingInterface) at hand, the implementation of a Single Custom Controller is now a lot simpler to describe.

1. As we discussed [above](#new-from-pkgcontrollerhttpsgithubcomrancherlassoblobmasterpkgcontroller), we know that our `ResourceEventHandler` will effectively enqueue the object onto the [`workqueue.DelayingInterface`](https://pkg.go.dev/k8s.io/client-go/util/workqueue#DelayingInterface) by calling `.Add("<namespace>/<name>")`.

2. When we start our controller, with the call to `Start(ctx context.Context, workers int)`, we will simply start our `cache.SharedIndexInformer`, wait for it to be ready (check if `cache.SharedIndexInformer.HasSynced` is true), and call `c.run(workers, ctx.Done())` **in a separate goroutine**.

> **Note:** Why do we call `run` in a separate goroutine?
>
> `Start` is not expected to be a blocking call. This is why binaries that start controllers tend to end with something like `<-cmd.Context().Done()`

> **Note:** What is the context provided?
>
> Generally this will be a context that listens to OS signals to trigger a graceful shutdown, i.e. `ctx := signals.SetupSignalHandler(context.Background())`

3. On calling `run`, we add the original deferred `[]startKey` to the `workqueue.DelayingInterface` for processing and call `runWorker` in as many goroutines as workers provided with the following code:

```go
// Launch two workers to process Foo resources
for i := 0; i < workers; i++ {
    go wait.Until(c.runWorker, time.Second, stopCh)
}
```

> **Note:** What is `wait.Until`?
>
> It just recalls `runWorker` any time it exits out after the duration provided until the `stopCh` exits.


4. For each worker goroutine that is running `runWorker`, we infinitely call `processNextWorkItem`

```go
func (c *controller) runWorker() {
	for c.processNextWorkItem() {
	}
}
```

5. When we process a specific work item, we get the specific item from the `workqueue.DelayingInterface` and process it, logging any errors we might see unless it was due to a re-enqueue (which may happen if the `resourceVersion` of the Kubernetes resource is out-of-date):


```go
func (c *controller) processNextWorkItem() bool {
	obj, shutdown := c.workqueue.Get()

	if shutdown {
		return false
	}

	if err := c.processSingleItem(obj); err != nil {
		if !strings.Contains(err.Error(), "please apply your changes to the latest version and try again") {
			log.Errorf("%v", err)
		}
		return true
	}

	return true
}
```

6. Finally, we process the item itself in that given worker goroutine, which eventually calls the `OnChange` operation from our single `Handler` and logs a metric. If there's an error, we add the item back to the workqueue using the delaying interface (which is how we implement Exponential Backoff on controller retries, since the original `workqueue.RateLimitingInterface` provided is generally one that rate limits in that fashion):

```go
func (c *controller) processSingleItem(obj interface{}) error {
	var (
		key string
		ok  bool
	)

	defer c.workqueue.Done(obj)

	if key, ok = obj.(string); !ok {
		c.workqueue.Forget(obj)
		log.Errorf("expected string in workqueue but got %#v", obj)
		return nil
	}
	if err := c.syncHandler(key); err != nil {
		c.workqueue.AddRateLimited(key)
		return fmt.Errorf("error syncing '%s': %s, requeuing", key, err.Error())
	}

	c.workqueue.Forget(obj)
	return nil
}

func (c *controller) syncHandler(key string) error {
	obj, exists, err := c.informer.GetStore().GetByKey(key)
	if err != nil {
		metrics.IncTotalHandlerExecutions(c.name, "", true)
		return err
	}
	if !exists {
		return c.handler.OnChange(key, nil)
	}

	return c.handler.OnChange(key, obj.(runtime.Object))
}
```

We have now implemented our first feature: **Re-trigger the reconciliation process on handler errors and handle reconciliation in parallel**!
