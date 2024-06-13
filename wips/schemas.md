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