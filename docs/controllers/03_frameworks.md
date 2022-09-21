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

The `New` function in the `pkg/controller` module is the entrypoint for understanding how [Lasso](https://github.com/rancher/lasso) works to solve the first feature that our Controller Framework needs to implement. As a reminder, what we would like Lasso to implement for this feature is everything below the dotted line in this diagram:

![Client-Go Controller Diagram](../images/client-go-controller-interaction.jpg)


---
---
---
---

# WIP: Do Not Read

### Special Topic: [OpenAPI Schemas](https://spec.openapis.org/oas/latest.html) and [Swagger](https://swagger.io/docs/specification/2-0/what-is-swagger/)

In the world of HTTP APIs, it's common for any program that offers up an HTTP API to provide an OpenAPI Specification, a JSON-based specification that is described on [OpenAPI's own website](https://spec.openapis.org/oas/latest.html) as follows:

> The OpenAPI Specification (OAS) defines a standard, programming language-agnostic interface description for HTTP APIs, which allows both humans and computers to discover and understand the capabilities of a service without requiring access to source code, additional documentation, or inspection of network traffic

Swagger was the original specification (and suite of tools around the specification) that OpenAPI emerged from, which is why you will commonly see that OpenAPI specifications are outlined in a file called the `swagger.json`, as seen in Kubernetes's own repo [under `api/open-api-spec/swagger.json`](https://github.com/kubernetes/kubernetes/blob/release-1.5/api/openapi-spec/swagger.json). In [Swagger's own words](https://swagger.io/docs/specification/2-0/what-is-swagger/):

> Swagger allows you to describe the structure of your APIs so that machines can read them. The ability of APIs to describe their own structure is the root of all awesomeness in Swagger. Why is it so great? Well, by reading your API’s structure, we can automatically build beautiful and interactive API documentation. We can also automatically generate client libraries for your API in many languages and explore other possibilities like automated testing. Swagger does this by asking your API to return a YAML or JSON that contains a detailed description of your entire API. This file is essentially a resource listing of your API which adheres to OpenAPI Specification. The specification asks you to include information like:
>
> What are all the operations that your API supports?
>
> What are your API’s parameters and what does it return?
>
> Does your API need some authorization?
>
> And even fun things like terms, contact information and license to use the API.

In the Kubernetes world, every Kubernetes resource is required to have an `OpenAPISchema` that provides this specification, which allows Kubernetes clients like `kubectl` or your own controllers to understand how to **locally validate** the structure of the Kubernetes resources that you are passing to and getting from the API Server **without contacting the API Server for verification every single time**.

> **Note:** This schema is also generally generated automatically for you via code generation from `go generate` by most controller frameworks, as we will discuss later as part of the deep dive into [Wrangler](#wranglerhttpsgithubcomrancherwrangler).

### The [`discovery.Interface`](https://pkg.go.dev/k8s.io/client-go/discovery#DiscoveryInterface)

```go
type DiscoveryInterface interface {
	RESTClient() restclient.Interface
	ServerGroupsInterface
	ServerResourcesInterface
	ServerVersionInterface
	OpenAPISchemaInterface
	OpenAPIV3SchemaInterface
}

type ServerGroupsInterface interface {
	// ServerGroups returns the supported groups, with information like supported versions and the
	// preferred version.
	ServerGroups() (*metav1.APIGroupList, error)
}

type ServerResourcesInterface interface {
	// ServerResourcesForGroupVersion returns the supported resources for a group and version.
	ServerResourcesForGroupVersion(groupVersion string) (*metav1.APIResourceList, error)
	// ServerGroupsAndResources returns the supported groups and resources for all groups and versions.
	//
	// The returned group and resource lists might be non-nil with partial results even in the
	// case of non-nil error.
	ServerGroupsAndResources() ([]*metav1.APIGroup, []*metav1.APIResourceList, error)
	// ServerPreferredResources returns the supported resources with the version preferred by the
	// server.
	//
	// The returned group and resource lists might be non-nil with partial results even in the
	// case of non-nil error.
	ServerPreferredResources() ([]*metav1.APIResourceList, error)
	// ServerPreferredNamespacedResources returns the supported namespaced resources with the
	// version preferred by the server.
	//
	// The returned resource list might be non-nil with partial results even in the case of
	// non-nil error.
	ServerPreferredNamespacedResources() ([]*metav1.APIResourceList, error)
}

type ServerVersionInterface interface {
	// ServerVersion retrieves and parses the server's version (git version).
	ServerVersion() (*version.Info, error)
}

type OpenAPISchemaInterface interface {
	// OpenAPISchema retrieves and parses the swagger API schema the server supports.
	OpenAPISchema() (*openapi_v2.Document, error)
}

type OpenAPIV3SchemaInterface interface {
	OpenAPIV3() openapi.Client
}
```

### The [`meta.RESTMapper`](https://pkg.go.dev/k8s.io/apimachinery/pkg/api/meta#RESTMapper)

Discussion about GVK v.s. GVR

> You’ll also hear mention of resources on occasion. A resource is simply a use of a Kind in the API. Often, there’s a one-to-one mapping between Kinds and resources. For instance, the pods resource corresponds to the Pod Kind. However, sometimes, the same Kind may be returned by multiple resources. For instance, the Scale Kind is returned by all scale subresources, like deployments/scale or replicasets/scale. This is what allows the Kubernetes HorizontalPodAutoscaler to interact with different resources. With CRDs, however, each Kind will correspond to a single resource.

> Notice that resources are always lowercase, and by convention are the lowercase form of the Kind.

Maps GVR -> GVK

### The 

### The [`runtime.Scheme`](https://pkg.go.dev/k8s.io/client-go/pkg/runtime#Scheme)



In [Lasso](https://github.com/rancher/lasso), 

### [Wrangler](https://github.com/rancher/wrangler)

TBD