## Introduction To Kubernetes Clients

### What is a Kubernetes Client?

A Kubernetes client is a **process** that interacts with the [Kubernetes API](https://kubernetes.io/docs/reference/using-api/api-concepts/).

From the [Kubernetes Docs](https://kubernetes.io/docs/reference/using-api/api-concepts/):

```
The Kubernetes API is a resource-based (RESTful) programmatic interface provided via HTTP. It supports retrieving, creating, updating, and deleting primary resources via the standard HTTP verbs (POST, PUT, PATCH, DELETE, GET).
...
Kubernetes supports efficient change notifications on resources via watches. Kubernetes also provides consistent list operations so that API clients can effectively cache, track, and synchronize the state of resources.
```

> **Note:** the Kubernetes API is exposed on the endpoint served by the `kube-apiserver` process on controlplane nodes, as mentioned [in the previous section](./00_introduction.md#what-does-it-mean-to-install-kubernetes-onto-a-set-of-servers).

> **Note:** "efficient change notifications on resources via watches" is achievable via one of the core features of using etcd as the backing database for Kubernetes, as mentioned [in the previous section](./00_introduction.md#what-is-etcd).

The most popular example of a Kubernetes client is `kubectl`; under the hood, all `kubectl` calls are just translated to the corresponding HTTP API calls to the Kubernetes API Server endpoint for a particular Kubernetes resource. The endpoint and authentication information used to construct that HTTP API call are contained within your KUBECONFIG file, which is why kubectl requires your KUBECONFIG to be able to execute requests like `kubectl get nodes`.

### Example: Watch Kubernetes Resources With Kubectl

On one terminal window that has access to your Kubernetes cluster, run the following command to watch all `ConfigMaps` in your cluster:

```bash
kubectl get configmaps -n default --watch
```

On another terminal windows, run the following two commands and watch the output on the first terminal window:

```bash
kubectl apply -f examples/configmap-1.yaml

kubectl apply -f examples/configmap-2.yaml

kubectl delete -f examples/configmap-2.yaml
```

On each operation, you should see a new object get printed out, which signifies that a change has been observed to that ConfigMap resource.
 
This shows the generic principle of how a Kubernetes client can watch for changes and do an action (i.e. print to stdout).

### The Anatomy of A Kubernetes Resource

Each version of Kubernetes comes with [API Reference documentation](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.25/) that defines the standard Kubernetes Resource definitions that can be queried from any Kubernetes cluster of that version; these resources are managed by the default Kubernetes controllers (generally `kube-controller-manager`).

However, when defining a Custom Resource Definition (the definition of a non-standard resource stored in the Kubernetes API, usually defined by a specific controller that manages Custom Resources of those types), there are still standard interfaces that your Custom Resource Definition needs to satisfy.

Namely, any generic Kubernetes object can be defined as a Go type as long as it implements the following two interfaces:

#### The [runtime.Object](https://pkg.go.dev/k8s.io/apimachinery/pkg/runtime#Object) Interface

```go
// package runtime
type Object interface {
	GetObjectKind() schema.ObjectKind
	DeepCopyObject() Object
}

// package schema
type ObjectKind interface {
	// SetGroupVersionKind sets or clears the intended serialized kind of an object. Passing kind nil
	// should clear the current setting.
	SetGroupVersionKind(kind GroupVersionKind)
	// GroupVersionKind returns the stored group, version, and kind of an object, or an empty struct
	// if the object does not expose or provide these fields.
	GroupVersionKind() GroupVersionKind
}

type GroupVersionKind struct {
	Group   string
	Version string
	Kind    string
}
```

This is the most generic interface that every Kubernetes object must satisfy; the object must be able to identifiable by a GVK (Group, Version, Kind).

The [kube-builder book](https://book.kubebuilder.io/cronjob-tutorial/gvks.html) has a fantastic introduction to what GVKs are (as opposed to GVRs, which correspond to one or more GVKs, but generally one), but generally this corresponds to the following fields in a Kubernetes resource:

```yaml
apiVersion: <group>/<version> # catalog.cattle.io/v1
kind: <kind> # ChartRepository
```

In general, the `kind` should represents the name of the specific named struct type in Golang that represents your object; more on this later when we talk about the [Controller Frameworks](./03_frameworks.md).

To automatically have your CRD type implement this interface, you generally embed the following object into your CRD struct definition:

```go
// import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
type MyCRD struct {
    metav1.TypeMeta   `json:",inline"`
}
```

####  The [metav1.Object](https://pkg.go.dev/k8s.io/apimachinery/pkg/apis/meta/v1#Object) Interface

```go
type Object interface {
	GetNamespace() string
	SetNamespace(namespace string)
	GetName() string
	SetName(name string)
	GetGenerateName() string
	SetGenerateName(name string)
	GetUID() types.UID
	SetUID(uid types.UID)
	GetResourceVersion() string
	SetResourceVersion(version string)
	GetGeneration() int64
	SetGeneration(generation int64)
	GetSelfLink() string
	SetSelfLink(selfLink string)
	GetCreationTimestamp() Time
	SetCreationTimestamp(timestamp Time)
	GetDeletionTimestamp() *Time
	SetDeletionTimestamp(timestamp *Time)
	GetDeletionGracePeriodSeconds() *int64
	SetDeletionGracePeriodSeconds(*int64)
	GetLabels() map[string]string
	SetLabels(labels map[string]string)
	GetAnnotations() map[string]string
	SetAnnotations(annotations map[string]string)
	GetFinalizers() []string
	SetFinalizers(finalizers []string)
	GetOwnerReferences() []OwnerReference
	SetOwnerReferences([]OwnerReference)
	GetManagedFields() []ManagedFieldsEntry
	SetManagedFields(managedFields []ManagedFieldsEntry)
}
```

The `metav1.Object` interface represents all of the metadata information that every Kubernetes resource is expected to have that is stored in the `metadata` field of an object, such as a timestamp that encodes when it was created or deleted, labels and annotation, etc.

Generally, when you receive a `runtime.Object` instance, it is expected that you can use [`meta.Accessor`](https://pkg.go.dev/k8s.io/apimachinery/pkg/api/meta#Accessor) to access all of these fields that are generically expected for Kubernetes resources to have defined.

To automatically have your CRD type implement this interface, you generally embed the following object into your CRD struct definition:

```go
// import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
type MyCRD struct {
    metav1.ObjectMeta `json:"metadata,omitempty"`
}
```

### Listing Kubernetes Resources

Generally, when a Kubernetes client requests a `List` of Kubernetes resources, instead of returning a slice of objects the Kubernetes API returns a special type of object: [`metav1.List`](https://pkg.go.dev/k8s.io/apimachinery/pkg/apis/meta/v1#List) object. 

This is effectively a list of `runtime.Object`s (also expected to be `metav1.Object`s) that is encapsulated in some metadata information, most notably whether this is a partial list or not (informed by the `metav1.List`'s `metadata.continue` and `metadata.remainingItemCount` fields).

```go
// package metav1
type List struct {
	TypeMeta `json:",inline"`
	// Standard list metadata.
	// More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds
	// +optional
	ListMeta `json:"metadata,omitempty" protobuf:"bytes,1,opt,name=metadata"`

	// List of objects
	Items []runtime.RawExtension `json:"items" protobuf:"bytes,2,rep,name=items"`
}

type ListMeta struct {
	// Deprecated: selfLink is a legacy read-only field that is no longer populated by the system.
	// +optional
	SelfLink string `json:"selfLink,omitempty" protobuf:"bytes,1,opt,name=selfLink"`

	// String that identifies the server's internal version of this object that
	// can be used by clients to determine when objects have changed.
	// Value must be treated as opaque by clients and passed unmodified back to the server.
	// Populated by the system.
	// Read-only.
	// More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#concurrency-control-and-consistency
	// +optional
	ResourceVersion string `json:"resourceVersion,omitempty" protobuf:"bytes,2,opt,name=resourceVersion"`

	// continue may be set if the user set a limit on the number of items returned, and indicates that
	// the server has more data available. The value is opaque and may be used to issue another request
	// to the endpoint that served this list to retrieve the next set of available objects. Continuing a
	// consistent list may not be possible if the server configuration has changed or more than a few
	// minutes have passed. The resourceVersion field returned when using this continue value will be
	// identical to the value in the first response, unless you have received this token from an error
	// message.
	Continue string `json:"continue,omitempty" protobuf:"bytes,3,opt,name=continue"`

	// remainingItemCount is the number of subsequent items in the list which are not included in this
	// list response. If the list request contained label or field selectors, then the number of
	// remaining items is unknown and the field will be left unset and omitted during serialization.
	// If the list is complete (either because it is not chunking or because this is the last chunk),
	// then there are no more remaining items and this field will be left unset and omitted during
	// serialization.
	// Servers older than v1.15 do not set this field.
	// The intended use of the remainingItemCount is *estimating* the size of a collection. Clients
	// should not rely on the remainingItemCount to be set or to be exact.
	// +optional
	RemainingItemCount *int64 `json:"remainingItemCount,omitempty" protobuf:"bytes,4,opt,name=remainingItemCount"`
}

// package runtime
type RawExtension struct {
	// Raw is the underlying serialization of this object.
	//
	// TODO: Determine how to detect ContentType and ContentEncoding of 'Raw' data.
	Raw []byte `json:"-" protobuf:"bytes,1,opt,name=raw"`
	// Object can hold a representation of this extension - useful for working with versioned
	// structs.
	Object Object `json:"-"`
}
```

### Special Topic: How Does `kubectl` Translate Requests To HTTP API Calls?

Under the hood, `kubectl` simply takes your KUBECONFIG and creates a `rest.Config` object from it via one of the [`clientcmd.New*ClientConfig`](https://pkg.go.dev/k8s.io/client-go/tools/clientcmd#NewClientConfigFromBytes) functions.

Once `kubectl` has a `rest.Config`, it can simply use that to get a [`rest.RESTClient`](https://pkg.go.dev/k8s.io/client-go/rest#RESTClient) object using a function like [`rest.RESTClientFor`](https://pkg.go.dev/k8s.io/client-go/rest#RESTClientFor) that provides the following fields to construct a request to the Kubernetes API:

```go
func (c *RESTClient) APIVersion() schema.GroupVersion
func (c *RESTClient) Delete() *Request
func (c *RESTClient) Get() *Request
func (c *RESTClient) GetRateLimiter() flowcontrol.RateLimiter
func (c *RESTClient) Patch(pt types.PatchType) *Request
func (c *RESTClient) Post() *Request
func (c *RESTClient) Put() *Request
func (c *RESTClient) Verb(verb string) *Request
```

In turn, depending on the operation that the user would like to perform, the `rest.Request` object can be used to pass in additional fields to the request or marshall a returned object back into a `runtime.Object` (done by executing `request.Do(ctx).Into(myObj)`).

```go
func (r *Request) AbsPath(segments ...string) *Request
func (r *Request) BackOff(manager BackoffManager) *Request
func (r *Request) Body(obj interface{}) *Request
func (r *Request) Do(ctx context.Context) Result
func (r *Request) DoRaw(ctx context.Context) ([]byte, error)
func (r *Request) MaxRetries(maxRetries int) *Request
func (r *Request) Name(resourceName string) *Request
func (r *Request) Namespace(namespace string) *Request
func (r *Request) NamespaceIfScoped(namespace string, scoped bool) *Request
func (r *Request) Param(paramName, s string) *Request
func (r *Request) Prefix(segments ...string) *Request
func (r *Request) RequestURI(uri string) *Request
func (r *Request) Resource(resource string) *Request
func (r *Request) SetHeader(key string, values ...string) *Request
func (r *Request) SpecificallyVersionedParams(obj runtime.Object, codec runtime.ParameterCodec, version schema.GroupVersion) *Request
func (r *Request) Stream(ctx context.Context) (io.ReadCloser, error)
func (r *Request) SubResource(subresources ...string) *Request
func (r *Request) Suffix(segments ...string) *Request
func (r *Request) Throttle(limiter flowcontrol.RateLimiter) *Request
func (r *Request) Timeout(d time.Duration) *Request
func (r *Request) URL() *url.URL
func (r *Request) Verb(verb string) *Request
func (r *Request) VersionedParams(obj runtime.Object, codec runtime.ParameterCodec) *Request
func (r *Request) WarningHandler(handler WarningHandler) *Request
func (r *Request) Watch(ctx context.Context) (watch.Interface, error)
```

## Next Up

Next, we will talk introduce the basics of Kubernetes Controllers by discussing the [Informer Pattern](./02_informers.md)!