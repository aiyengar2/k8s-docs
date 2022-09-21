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
5. On first popping off the object from the `cache.DeltaFIFO`, the `cache.SharedIndexInformer` will store the updated Kubernetes resource (or delete it, if it has been removed) in the `cache.ThreadSafeStore`, by default using `<namespace>/<name>` as the key. If more indexers are added, each index will be calculated on entry into the cache at this step. This `cache.Store` is accessible by calling the `cache.SharedIndexInformer.GetStore()` function.
6. After adding the object to our `cache.ThreadSafeStore`, every `ResourceEventHandler` registered with `cache.SharedIndexInformer.AddResourceEventHandler(ResourceEventHandler)` or `cache.SharedIndexInformer.AddResourceEventHandlerWithResyncPeriod(ResourceEventHandler, time.Duration)` will be called in order. **However, the `ResourceEventHandler` will only be called once per enqueue; if there is an error in handling of the ResourceEventHandler, it will be up to the ResourceEventHandler to seperately handle re-enqueue logic.**
> **Note:** This comes directly from the [`cache.SharedInfomer`](https://pkg.go.dev/k8s.io/client-go/tools/cache#SharedInformer) Go documentation in the following excerpt:
>
> A client must process each notification promptly; a SharedInformer is not engineered to deal well with a large backlog of notifications to deliver. Lengthy processing should be passed off to something else, for example through a `client-go/util/workqueue`.

In the next part, we will talk about how what is **below the dotted line and more**  by looking at two Controller Frameworks: [`rancher/lasso`](https://github.com/rancher/lasso) and [`rancher/wrangler`](https://github.com/rancher/wrangler).

### Why Do We Need Controller Frameworks?

While the `cache.SharedIndexInformer` allows us to satisfy the definition of the `Informer` we listed above, generally Custom Controllers that are written for Kubernetes need the following additional features:
1. **Re-trigger the reconciliation process on handler errors**: as mentioned above, this is not suitable for the `cache.SharedIndexInformer` to handle, so this is genererally achieved by leveraging the [`k8s.io/client-go/util/workqueue`](https://pkg.go.dev/k8s.io/client-go/util/workqueue) package.
2. **Manage creating Kubernetes clients and `cache.SharedIndexInformers` on multiple types of Kubernetes resources in an resource efficient manner**: generally this will involve creating constructs like a `Shared*Factory` that will ensure that there's only one copy of a given client or informer that is given to all parts of your code that need it. This is also where the [`runtime.Scheme`](https://pkg.go.dev/gopkg.in/kubernetes/client-go.v2/pkg/runtime#Scheme), a construct which helps map Go types to GVKs and vice-versa, comes into play.
3. **Generate code to make it easier to define custom types and controllers**: as listed on the section on the [Anatomy of a Kubernetes Resources](./01_clients.md#the-anatomy-of-a-kubernetes-resource), any custom type that is supposed to represent a Kubernetes resource needs to implement certain functions to be considered a Kubernetes resource, such as `GetObjectKind()` or `DeepCopyObject()` (which satisfies the `runtime.Object` interface), and be added to a default `runtime.Scheme` to be used in `Shared*Factory` constructs. This is generally handled by code generation via `go generate` commands, which will create **typed** functions, eliminating the need for developers to type cast objects received by generic Handler functions.
4. **Define helper code to encapsulte common controller design patterns**: these include special types of handlers such as `Register*StatusHandler`, `Register*GeneratingHandler`, `relatedresource.Watch` that simplify the logic necessary to be written on a controller **if it falls under a specific controller design pattern**.

In the next part, we will talk about how the first two features are implemented by [`rancher/lasso`](https://github.com/rancher/lasso).

In the following part, we will talk about how the second two features are implemented by [`rancher/wrangler`](https://github.com/rancher/wrangler).

### [Lasso](https://github.com/rancher/lasso)



### [Wrangler](https://github.com/rancher/wrangler)

TBD