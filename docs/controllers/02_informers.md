## Introduction to the Informer Pattern

The `Informer` pattern is the basic design pattern that is used when implementing a single Kubernetes `Controller` on a single type of Kubernetes resource. 

Simply put, an `Informer` is a pattern for creating an in-memory object that is **"informed"** of changes to certain objects that fall under a specific Kubernetes resource's type.

In practice, we want the `Informer` to do two things on being "informed" of a change:
1. **Store the "current state of the world" in-memory**: Considering how frequently we run controller handlers that need to get objects (for reference, most Rancher controllers run about 50 worker threads simultaenously that are executing handlers at the exact same time), it would be incredibly slow and inefficient if we were to query the Kubernetes API every time we need to know the current state of something.
  - Note: It's generally fine if the current state of the object in our in-memory store is **eventually consistent** with the real state of the world; informers generally have a concept of a `ResyncPeriod` (usually 10 hours) in which they periodically request for a list of all resources of a given type to "fix" what has been stored. This has to do with the fact that controllers follow an "edge-triggered" design pattern that is prone to errors due to possible interrupts; if you want to dig into the technicalities, please read [this article on Level Triggering and Reconciliation in Kubernetes](https://medium.com/hackernoon/level-triggering-and-reconciliation-in-kubernetes-1f17fe30333d)
2. **Trigger an action on "processing" a change to a resource**: The action performed here would likely be some form of **"reconciliation"** on the "current state of the world" (for example, updating status fields on seeing a new object be created)

In this section, we will discuss the underlying design of the [`cache.SharedIndexInformer`](https://pkg.go.dev/k8s.io/client-go/tools/cache#NewSharedIndexInformer), a special type of `Informer` that the `tools/cache` package within `k8s.io/client-go` implements; colloquially (and generally erroneously), this is what is commonly referred to as a single Kubernetes "Controller".

> **Note:** A lot of the topics covered in the next section is covered phenomenally in a series of blog posts starting with [part 0](https://lairdnelson.wordpress.com/2018/01/07/understanding-kubernetes-tools-cache-package-part-0/) here. The content below is a rough summary of the content from the article; for a deeper dive, I recommend reading starting at part 0.

> **Note:** We will not discuss how to manage multiple `cache.SharedIndexInformers` at once until we get to the section on [Lasso](./03_frameworks.md#lassohttpsgithubcomrancherlasso) or [Wrangler](./03_frameworks.md#wranglerhttpsgithubcomrancherwrangler), which are roughly Rancher's versions of the [kubernetes-sigs/controller-runtime](https://github.com/kubernetes-sigs/controller-runtime) + [kubernetes-sigs/kubebuilder](https://github.com/kubernetes-sigs/kubebuilder) frameworks, respectively. 
> However, it should be noted that all of these frameworks are built on top of the same [`tools/cache`](https://pkg.go.dev/k8s.io/client-go/tools/cache) package from `k8s.io/client-go`.

### `tools/cache` Primitive Interfaces

Before attempting to define what a `Controller` is, first we will describe the two low-level interfaces defined by the [`tools/cache`](https://pkg.go.dev/k8s.io/client-go/tools/cache) package.

#### The [`cache.ListerWatcher`](https://pkg.go.dev/k8s.io/client-go/tools/cache#ListerWatcher)

```go
type ListerWatcher interface {
	Lister
	Watcher
}

type Lister interface {
	// List should return a list type object; the Items field will be extracted, and the
	// ResourceVersion field will be used to start the watch in the right place.
	List(options metav1.ListOptions) (runtime.Object, error)
}

type Watcher interface {
	// Watch should begin a watch at the specified version.
	Watch(options metav1.ListOptions) (watch.Interface, error)
}
```

The `cache.ListerWatcher` is an interface that can do two things:
- `List(options metav1.ListOptions)` returns a single List-type Kubernetes resource (see section above on [Lists](#listing-kubernetes-resources)) based on the provided options
- `Watch(options metav1.ListOptions) (watch.Interface, error)`: returns a [`watch.Interface`](https://pkg.go.dev/k8s.io/apimachinery/pkg/watch#Interface), which is an interface of its own that can return a Go channel (`ResultChan() <-chan watch.Event`), where each [`watch.Event`](https://pkg.go.dev/k8s.io/apimachinery/pkg/watch#Event) contains the current version of the `runtime.Object` in the API and the `watch.EventType` that object experienced (i.e. "ADDED", "MODIFIED", "DELETED", "BOOKMARK", "ERROR").

> **Note:** If you recall the section above on [how kubectl translates requests into HTTP API calls](#special-topic-how-does-kubectl-translate-requests-to-http-api-calls), the [`rest.RESTClient`](https://pkg.go.dev/k8s.io/client-go/rest#RESTClient) supports:
> - Getting a particular resource (including getting a `metav1.List` resource, like our `metav1.List` function requires)
> -`Watch`ing on a particular resource by returning a `watch.Interface`. 
>
> Therefore, all we need to define a `cache.ListerWatcher` is a simple `rest.RESTClient`, which can be created as long as we have a KUBECONFIG file.
>
> In addition, if you recall the section on [etcd](./00_introduction.md#what-is-etcd), we know that listing and watching resources are two of the things that etcd does very efficiently; therefore, it is perfectly fine for this interface to form the backbone of how we define ingesting events for `Controllers`!

#### The [`cache.Store`](https://pkg.go.dev/k8s.io/client-go/tools/cache#Store)

```go
type Store interface {
	Add(obj interface{}) error
	Update(obj interface{}) error
	Delete(obj interface{}) error
	List() []interface{}
	ListKeys() []string
	Get(obj interface{}) (item interface{}, exists bool, err error)
	GetByKey(key string) (item interface{}, exists bool, err error)

	// Replace will delete the contents of the store, using instead the
	// given list. Store takes ownership of the list, you should not reference
	// it after calling this function.
	Replace([]interface{}, string) error
	Resync() error
}
```

The `cache.Store` interface is a generic object storage interface (note that it does not care about whether the object implements `runtime.Object`!); it represents the cache of information that is stored from the Kubernetes API.

Since it is so generically defined, a Store can be anything in the backend; the simplest version of a `cache.Store` is the [`cache.ThreadSafeStore`](https://pkg.go.dev/k8s.io/client-go/tools/cache#ThreadSafeStore), a simple implementation of a `cache.Store` that supports indexing and can be safely accessed by multiple goroutines at the same time; 

> **Note:** Another form of a `cache.Store` that is not commonly directly used is an [`cache.ExpirationCache`](https://pkg.go.dev/k8s.io/client-go/tools/cache#ExpirationCache): a `cache.Store` that expires items contained within it after a certain amount of time. The expiration check will happen when you try to `Get` a resource from the `cache.Store` (which means that Reads are expensive; this is why it's preferred to use a ThreadSafeStore!)

> **Note:** For these type of stores, generally `Resync()` is a no-op. See the `cache.Queue` for examples of `cache.Store`s that implement `Resync()`.

#### The [`cache.Queue`](https://pkg.go.dev/k8s.io/client-go/tools/cache#Queue)

Leveraging the generic definition of a `cache.Store` interface, the `cache.Queue` is another interface that can be treated as a `cache.Store`, but the underlying object has the ability to additionally **process** items that were added to it; on processing an item, it will be removed from the `cache.Queue`.

> **Note:** A `cache.Queue` **embeds** `cache.Store`; this just means that anything that manages to satisfy the definition of a `cache.Queue` can also be used as a `cache.Store`.

```go
type Queue interface {
	Store

	// Pop blocks until there is at least one key to process or the
	// Queue is closed.  In the latter case Pop returns with an error.
	// In the former case Pop atomically picks one key to process,
	// removes that (key, accumulator) association from the Store, and
	// processes the accumulator.  Pop returns the accumulator that
	// was processed and the result of processing.  The PopProcessFunc
	// may return an ErrRequeue{inner} and in this case Pop will (a)
	// return that (key, accumulator) association to the Queue as part
	// of the atomic processing and (b) return the inner error from
	// Pop.
	Pop(PopProcessFunc) (interface{}, error)

	// AddIfNotPresent puts the given accumulator into the Queue (in
	// association with the accumulator's key) if and only if that key
	// is not already associated with a non-empty accumulator.
	AddIfNotPresent(interface{}) error

	// HasSynced returns true if the first batch of keys have all been
	// popped.  The first batch of keys are those of the first Replace
	// operation if that happened before any Add, AddIfNotPresent,
	// Update, or Delete; otherwise the first batch is empty.
	HasSynced() bool

	// Close the queue
	Close()
}
```

The [`cache.FIFO`](https://pkg.go.dev/k8s.io/client-go/tools/cache#FIFO) is the simplest object that implements the `cache.Queue` interface; similar to the `cache.ThreadSafeStore`, it can also be safely accessed by multiple goroutines at the same time.

However, unlike the `cache.ThreadSafeStore`, the `cache.FIFO` expects there to exist some sort of `keyFunc` that can be used to index each incoming object to a given `string` key, which is passed in on creating the FIFO (`func NewFIFO(keyFunc KeyFunc) *FIFO`). 

Under the hood, on inserting objects into the `cache.FIFO`, it will maintain two constructs:
- `items map[string]interface{}`: all items that have been seen thus far but are pending processing; the item will always be updated to the latest on every `Add` operation and will be removed after processing or on `Delete`.

> **Note:** the `items` field is also known as the "accumulator" field since it accumulates the latest definition of the object within the `cache.Queue`; in this case, we are accumulating by just storing the latest field, but other `cache.Queues` (namely the `DeltaFIFO` discussed in the next section) may accumulate more than just the latest object here.

- `queue []string`: a list of `strings` whose values come from calling `keyFunc(item)` on adding items to the queue

On calling `Pop(popFunc)`, the FIFO will pop the first key from the `fifo.queue` and see whether `items[key]` exists; if it does not exist, it will assume the item has already been processed or has been removed from processing and continue with the next item on the `fifo.queue`. 

If `items[key]` does exist, then by definition that must be the latest version of the item (since every `Add` operation **updates** the item in a common map), so the latest version of the object will be popped and processed. It will then pass in this item to the `popFunc` as its argument.

This provides the following guarantees listed on its documentation:

```
FIFO solves this use case:

- You want to process every object (exactly) once.
- You want to process the most recent version of the object when you process it.
- You do not want to process deleted objects, they should be removed from the queue.
- You do not want to periodically reprocess objects.
```

In addition to implementing the `cache.Queue` interface, a `cache.FIFO` has one additional function defined from its `cache.Store` interface: `Resync()`. This function ensures that every item in `fifo.items` is added to the `fifo.queue` if it does not exist, which triggers re-processing in case any items happened to not be processed.

#### The [`cache.DeltaFIFO`](https://pkg.go.dev/k8s.io/client-go/tools/cache#DeltaFIFO)

Similar to the `cache.FIFO` discussed above, the `cache.DeltaFIFO` is a more complex type of `cache.Queue` with a very similar implementation; this is also the more common variant of a `cache.Queue` that we will see used in controllers.

However, there are three key differences to how it is implemented:

- Unlike a normal `cache.FIFO`, the `cache.DeltaFIFO` stores `items map[string]cache.Deltas`, where [`cache.Deltas`](https://pkg.go.dev/k8s.io/client-go/tools/cache#Deltas) is a list of `cache.Delta` objects. `cache.Delta` objects have two fields: the `Object interface{}`, which represents the latest state of a given object, and `Type cache.DeltaType`, which represents the operation that resulted in this latest state ("Added", "Updated", "Deleted", "Replaced", "Sync"). On a Pop operation, a `cache.Deltas` object is therefore returned instead of the object itself.

> **Note:** The `cache.Delta` looks eerily familiar to the `watch.Event` that is emitted from the `watch.Interface`! Recognizing this will come in handy for the next section.

- The `cache.DeltaFIFO` additionally supports two special ways of adding items to the queue: `Replaced` or `Sync`. These variants of `Add` ensure that the `cache.Delta` object that is added has the specific `cache.DeltaType` added to it that marks the object as one that has been `Replaced` or `Sync`ed.

- The `cache.DeltaFIFO` supports the ability to provide `knownObjects KeyListGetter`, which is a type of object that implements `ListKeys() []string` and `GetByKey(key string) (value interface{}, exists bool, err error)`. It will change the behavior of the DeltaFIFO in the following operations:
  - On `Delete`: if the object is not known, do a no-op
  - On `Replace`: treats `deltaFifo.knownObjects` as the source of truth for whether an object is being replaced. If an object does not exist in `deltaFifo.knownObjects` mark it as `DeletedFinalStateUnknown`
  - On `Resync`: adds each object in `deltaFifo.knownObjects.ListKeys()` for processing

> **Note:** Why do we need the ability to provide a `knownObjects`?
>
> Unlike a `cache.FIFO`, the `cache.DeltaFIFO` stores just the deltas of a given object **until it is processed**; presumably, this means that it is designed to be used in conjunction with an actual index that is storing the latest version of an object (i.e. our current "state of the world" in memory)
> 
> Therefore, the `deltaFifo.knownObjects` provided to the `cache.DeltaFIFO` serves as a way to modify the behavior of the `DeltaFIFO` in accordance to what our current "state of the world" believes rather than purely based on the entries that have been added to the `cache.Queue`.

As a result, the `cache.DeltaFIFO` has a slightly different list of guarantees listed on its documentation:

```
DeltaFIFO solves this use case:

- You want to process every object change (delta) at most once.
- When you process an object, you want to see everything that's happened to it since you last processed it.
- You want to process the deletion of some of the objects.
- You might want to periodically reprocess objects.
```

Similar to `cache.FIFO`, the `cache.DeltaFIFO` also implements `Resync()` to satisfy the `cache.Store` interface. This function ensures that every item in `fifo.items` is added to the `fifo.queue` if it does not exist, which triggers re-processing in case any items happened to not be processed.

#### The [`cache.Reflector`](https://pkg.go.dev/k8s.io/client-go/tools/cache#Reflector)

Given the `cache.ListerWatcher` and the `cache.Store` / `cache.Queue` interfaces defined above, we now have the necessary constructs in order to define our first higher-level construct: the [`cache.Reflector`](https://pkg.go.dev/k8s.io/client-go/tools/cache#Reflector).


The `cache.Reflector` is an object that is created by composing a `cache.ListerWatcher` (derived from a Kubernetes client) and a `cache.Store` (generally the `cache.ThreadSafeStore` or `cache.DeltaFIFO`) together with three additional fields:
- The name of the reflector
- The expectedType of a reflector: used to type cast the object when added or removed from the `cache.Store`
- A resyncPeriod: triggers the `cache.Store`'s `Resync()` operation perodically. 

```go
func NewNamedReflector(name string, lw ListerWatcher, expectedType interface{}, store Store, resyncPeriod time.Duration) *Reflector
```

On starting a `cache.Reflector` by calling `reflector.Run(stopCh)`, the `cache.Reflector` will automatically handle the "plumbing" between the provided `cache.ListerWatcher` and the corresponding `cache.Store` to ensure that all entries that have been listed are added to the store and subsequent changes to resources indicated by the `watch.Interface` returned by the `listerWatcher.Watch` operation result in the corresponding operations being executed on the `cache.Store`.

### What is a [`cache.Controller`](https://pkg.go.dev/k8s.io/client-go/tools/cache#Controller)?

Finally, we can define what a `cache.Controller` is! The general interface that a `cache.Controller` looks like this:

```go
type Controller interface {
	// Run does two things.  One is to construct and run a Reflector
	// to pump objects/notifications from the Config's ListerWatcher
	// to the Config's Queue and possibly invoke the occasional Resync
	// on that Queue.  The other is to repeatedly Pop from the Queue
	// and process with the Config's ProcessFunc.  Both of these
	// continue until `stopCh` is closed.
	Run(stopCh <-chan struct{})

	// HasSynced delegates to the Config's Queue
	HasSynced() bool

	// LastSyncResourceVersion delegates to the Reflector when there
	// is one, otherwise returns the empty string
	LastSyncResourceVersion() string
}
```

However, in practice the way that you create a controller is by calling `cache.New(cache.Config)`, where `cache.Config` is defined as follows:

```go
type Config struct {
	// The queue for your objects - has to be a DeltaFIFO due to
	// assumptions in the implementation. Your Process() function
	// should accept the output of this Queue's Pop() method.
	Queue

	// Something that can list and watch your objects.
	ListerWatcher

	// Something that can process a popped Deltas.
	Process ProcessFunc

	// ObjectType is an example object of the type this controller is
	// expected to handle.  Only the type needs to be right, except
	// that when that is `unstructured.Unstructured` the object's
	// `"apiVersion"` and `"kind"` must also be right.
	ObjectType runtime.Object

	// FullResyncPeriod is the period at which ShouldResync is considered.
	FullResyncPeriod time.Duration

	// ShouldResync is periodically used by the reflector to determine
	// whether to Resync the Queue. If ShouldResync is `nil` or
	// returns true, it means the reflector should proceed with the
	// resync.
	ShouldResync ShouldResyncFunc

	// If true, when Process() returns an error, re-enqueue the object.
	// TODO: add interface to let you inject a delay/backoff or drop
	//       the object completely if desired. Pass the object in
	//       question to this interface as a parameter.  This is probably moot
	//       now that this functionality appears at a higher level.
	RetryOnError bool

	// Called whenever the ListAndWatch drops the connection with an error.
	WatchErrorHandler WatchErrorHandler

	// WatchListPageSize is the requested chunk size of initial and relist watch lists.
	WatchListPageSize int64
}
```

From here, given the structs that we defined above, the implementation of the `cache.Controller` should be straightforward; the `cache.Controller` is nothing more than a `cache.Reflector<cache.DeltaFIFO, cache.ListerWatcher>` that calls `reflector.Queue.Pop(ProcessFunc)` on a regular interval!

In other words, a `cache.Controller` is an **auto-populating and auto-processing `cache.Queue` of resource deltas**.

### What is a `SharedInformer`?

Once we have a an auto-populating and auto-processing `cache.Queue` of resource deltas in the form of a `cache.Controller`, we now have the ability to ingest events from the Kubernetes API server. However, as defined in [the start of this section](#introduction-to-the-informer-pattern), we'd like our informer to do two additional things:
1. **Store the "current state of the world" in-memory**
2. **Trigger an action on "processing" a change to a resource**

This is where the `cache.SharedIndexInformer` comes into play, which can simply be created by the following function:

`func NewSharedInformer(lw cache.ListerWatcher, exampleObject runtime.Object, defaultEventHandlerResyncPeriod time.Duration) SharedInformer`

```go
type SharedInformer interface {
	// AddEventHandler adds an event handler to the shared informer using the shared informer's resync
	// period.  Events to a single handler are delivered sequentially, but there is no coordination
	// between different handlers.
	AddEventHandler(handler ResourceEventHandler)
	// AddEventHandlerWithResyncPeriod adds an event handler to the
	// shared informer with the requested resync period; zero means
	// this handler does not care about resyncs.  The resync operation
	// consists of delivering to the handler an update notification
	// for every object in the informer's local cache; it does not add
	// any interactions with the authoritative storage.  Some
	// informers do no resyncs at all, not even for handlers added
	// with a non-zero resyncPeriod.  For an informer that does
	// resyncs, and for each handler that requests resyncs, that
	// informer develops a nominal resync period that is no shorter
	// than the requested period but may be longer.  The actual time
	// between any two resyncs may be longer than the nominal period
	// because the implementation takes time to do work and there may
	// be competing load and scheduling noise.
	AddEventHandlerWithResyncPeriod(handler ResourceEventHandler, resyncPeriod time.Duration)
	// GetStore returns the informer's local cache as a Store.
	GetStore() Store
	// GetController is deprecated, it does nothing useful
	GetController() Controller
	// Run starts and runs the shared informer, returning after it stops.
	// The informer will be stopped when stopCh is closed.
	Run(stopCh <-chan struct{})
	// HasSynced returns true if the shared informer's store has been
	// informed by at least one full LIST of the authoritative state
	// of the informer's object collection.  This is unrelated to "resync".
	HasSynced() bool
	// LastSyncResourceVersion is the resource version observed when last synced with the underlying
	// store. The value returned is not synchronized with access to the underlying store and is not
	// thread-safe.
	LastSyncResourceVersion() string

	// The WatchErrorHandler is called whenever ListAndWatch drops the
	// connection with an error. After calling this handler, the informer
	// will backoff and retry.
	//
	// The default implementation looks at the error type and tries to log
	// the error message at an appropriate level.
	//
	// There's only one handler, so if you call this multiple times, last one
	// wins; calling after the informer has been started returns an error.
	//
	// The handler is intended for visibility, not to e.g. pause the consumers.
	// The handler should return quickly - any expensive processing should be
	// offloaded.
	SetWatchErrorHandler(handler WatchErrorHandler) error

	// The TransformFunc is called for each object which is about to be stored.
	//
	// This function is intended for you to take the opportunity to
	// remove, transform, or normalize fields. One use case is to strip unused
	// metadata fields out of objects to save on RAM cost.
	//
	// Must be set before starting the informer.
	//
	// Note: Since the object given to the handler may be already shared with
	//	other goroutines, it is advisable to copy the object being
	//  transform before mutating it at all and returning the copy to prevent
	//	data races.
	SetTransform(handler TransformFunc) error
}
```

On running a `cache.SharedIndexInformer`, under the hood it configures a `cache.Config` that creates a `cache.Controller` that watches for entries from the provided `cache.ListerWatcher` and adds them into an auto-generated `cache.DeltaFIFO`. It also creates a `cache.Store` off the `cache.ThreadSafeStore` implementation to serves as our "current state of the world".

From there, it pre-defines a `ProcessFunc` for us that does two things:
1. Add, updates, or deletes the item that has been processed to the `cache.Store` after processing the deltas
2. Calls all the registered `cache.ResourceEventHandler`s on each call to process

Diagrammatically, it looks like this:

![Client-Go Controller Diagram](../images/client-go-controller-interaction.jpg)

### What is a `SharedIndexInformer`?

The SharedIndexInformer is the final version of our solution; it's nothing more than the same SharedInformer except you provide an `cache.Indexer` to it instead of expecting it to automatically create the `cache.Store` for you, where a `cache.Indexer` is nothing more than a Store with additional support for indexing (which is exactly the additional feature our [ThreadSafeStore](#the-cachestorehttpspkggodevk8sioclient-gotoolscachestore) supports!).

```go
type Indexer interface {
	Store
	// Index returns the stored objects whose set of indexed values
	// intersects the set of indexed values of the given object, for
	// the named index
	Index(indexName string, obj interface{}) ([]interface{}, error)
	// IndexKeys returns the storage keys of the stored objects whose
	// set of indexed values for the named index includes the given
	// indexed value
	IndexKeys(indexName, indexedValue string) ([]string, error)
	// ListIndexFuncValues returns all the indexed values of the given index
	ListIndexFuncValues(indexName string) []string
	// ByIndex returns the stored objects whose set of indexed values
	// for the named index includes the given indexed value
	ByIndex(indexName, indexedValue string) ([]interface{}, error)
	// GetIndexers return the indexers
	GetIndexers() Indexers

	// AddIndexers adds more indexers to this store.  If you call this after you already have data
	// in the store, the results are undefined.
	AddIndexers(newIndexers Indexers) error
}
```

## Next Up

Next, we will talk introduce the basics of [Controller Frameworks](./03_frameworks.md), specifically [Lasso](https://github.com/rancher/lasso) and [Wrangler](https://github.com/rancher/wrangler)!
