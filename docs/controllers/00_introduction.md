## Prerequisites

It is expected that the reader of this material has a basic familiarity with Kubernetes, such as that of an average Kubernetes user who has interacted with Kubernetes resources in a cluster before via `kubectl` or some via other UI  (e.g. the Rancher UI) that exposes the names of underlying Kubernetes resources like `Pods`, `Deployments`, `Services`, etc. 

A basic familiarity with Golang (concepts like `structs` or `interfaces`) is also presumed, especially in later sections.

## Introduction To Kubernetes

### What is Kubernetes?

Kubernetes is open-source orchestration software for deploying, managing, and scaling distributed "self-contained, mostly-environment-agnostic processes running in a sandbox" (i.e. `Containers`) running on one or more servers (i.e. `Nodes`) that have some daemon that can run `Containers` (i.e. `Container Runtime`, e.g. `Docker`) installed on them.

In essence, Kubernetes can be thought of as a multi-server equivalent of Docker: whereas executing `docker ps` will list all of the Docker-managed processes (`Containers`) running on your single server, in Kubernetes executing a `kubectl get pods --all-namespaces` will list all of the sets of Kubernetes-managed distributed processes (`Pods`) running on every server (`Node`) that has registered with the Kubernetes API (i.e. the equivalent of running `docker ps` on every node, with additonal metadata).

> **Note**: One thing to think about in this section is how Kubernetes is able to achieve setting desired values (i.e. "run this process") and retrieving set values (i.e. "what process are running?") in a **consistent way across multiple nodes**. 
>
> In a single server, you can store this information directly on your server in a way that can be retrievable by a client (i.e. the `docker` client), i.e.:
> - In a file in your filesystem
> - In-memory within a running process accessible via a Unix socket or network endpoint (i.e. the Docker daemon)
>
> However, if you needed to store this information across multiple nodes that could be de-provisioned or removed at any time, the only way to do this would be to store that information in a distributed database (e.g. [etcd](#what-is-etcd)) that serves as the endpoint that your client can communicate with.

> **Note**: Why does Kubernetes use Pods instead of Containers as the basic unit of compute?
> 
> A Pod represents a set of containers that form **a single logical unit** that is deployed together. This provides certain guarantees:
> - Containers in a single Pod are **always** deployed onto the same node (and are consequently always managed by the same container runtime, i.e. Docker on a particular host).
> - Containers in a single Pod exist in the same "sandbox" (equivalent to two processes sharing a single Linux **network namespace** described in more details [here](https://www.redhat.com/sysadmin/kubernetes-pod-network-communications)). This is why two containers running in the same pod cannot use the same port and can communicate via `localhost`.
> - Since they are managed by the same container runtime, they can also be configured to mount the same ephemeral (`emptyDir`) volumes that are only accessibe to containers in the Pod.
>
> As a result of these guarantees, you can treat containers running in a Pod the same way you would treat those same containers running on a single virtual host, which allows you to deploy applications that follow "single-node multiple-container" patterns (see `Single node, multiple container patterns` within [this article](https://www.weave.works/blog/container-design-patterns-for-kubernetes/), such as `Sidecar`, `Ambassador / Proxy`, or `Adapter`.

For a deeper dive into how processes are managed in Kubernetes, please read the docs on [Process Management In Kubernetes](../process_management/00_introduction.md).

### What Is Etcd?

As listed in `etcd`'s main page:

```
etcd is a strongly consistent, distributed key-value store that provides a reliable way to store data that needs to be accessed by a distributed system or cluster of machines. It gracefully handles leader elections during network partitions and can tolerate machine failure, even in the leader node.
```

On creating a Kubernetes cluster, a **subset** of your Kubernetes nodes will form an [etcd](https://etcd.io/) cluster, which will serve as the **backing database for all of your Kubernetes transactions** (i.e. creating, deleting, modifying, and managing Kubernetes resources).

As a result, when you run a command like `kubectl get pods --all-namespaces`, a component in Kubernetes (`kube-apiserver`) will respectively make a `list` call to the backing `etcd` database for all resources under the `Pod` key that have been stored and return the result of that call in a particular format back to the user.

> **Note**: Why does Kubernetes use etcd? Why not use any other distributed key-value store?
> 
> Aside from the fact that it is a consistent, distributed key-value store that allows clients to easily be able to `list` the current state of the world, one of the core features that etcd offers is the ability to efficiently **`watch` for specific keys or directories for changes and react to changes in values**. 
> 
> The fact that etcd can do efficient `list` and `watch` operations is critical for the design of `Controllers`, since the basic `Controller` is defined on top of a `Client` that supports the `ListerWatcher` interface; that is, one that can `List` Kubernetes resources and set a `Watch` for changes to Kubernetes resources.
>
> See the page on [Informers](./02_informers.md#introduction-to-the-informer-pattern) for more information.

### What Does It Mean To "Install" Kubernetes Onto A Set Of Servers?

Typically, each `Node` (server) in Kubernetes will take on one or more of these responsibilities:
- **Etcd Node**: nodes that form the `etcd` cluster, as described [above](#what-is-etcd)
- **Controlplane Node**: nodes that each run the following Kubernetes **node-agnostic** internal components
  - API Server: `kube-apiserver`, which is the main entrypoint for HTTP requests to the [Kubernetes API](https://kubernetes.io/docs/reference/using-api/api-concepts/)
  - Default Kubernetes controllers: **(Not relevant for this document)**
    - `kube-controller-manager`: queries API Server to manage most default resources like `Node`, `Pods`, `Deployments`, `Services`, `ServiceAccounts`, etc.
    - `kube-scheduler`: queries API Server to watch for `Pods` and assign `Nodes` to them based on topology constraints (`nodeSelectors`, `tolerations`, etc.)
    - `cloud-controller-manager`: queries API Server to manage cloud-specific control logic
- **Worker Node**: nodes that run the following Kubernetes **node-specific** internal components
  - Container Runtime [Shim](https://en.wikipedia.org/wiki/Shim_(computing)) (`kubelet`): queries API Server to watch for `Pods` that have already been assigned the `Node` this kubelet is running on (i.e. those that have been processed by `kube-scheduler`) to appropriately ask the Container Runtime (i.e. Docker) to create, recreate, or remove `Containers` on the host accordingly
  - Network Proxy / Network Rule Manager (`kube-proxy`): queries API Server to watch for `Pods`, `Services`, and other resources to manage your node-specific network rules (i.e. `iptables`); for example, this component ensures that your node knows to accept and route incoming traffic to a `Pod` or `Service`'s IP address to the corresponding container running on the node instead of ignoring it, which would be default behavior of any server on seeing traffic from an IP address that is not the node's IP address. It also ensures that outbound traffic is properly sent to the right IP address. **In other words, this is what forms the definition of a Kubernetes cluster network**.

> **Note:** A cluster needs at least one controlplane node, an odd number of etcd nodes (to have a quorom for leader election), and at least one worker node to successfully run Kubernetes. A single-node Kubernetes cluster is one that contains a node that satisfies all responsibilities (i.e. has all the internal Kubernetes components running, from `etcd` to `kube-apiserver` to default controllers to worker components).
>
> Please see [Kubernetes's docs on internal components](https://kubernetes.io/docs/concepts/overview/components/) for more information on what these individual processes do on each host.

When we say that Kubernetes has been "installed" onto a node, that means that the above internal components are successfully configured and running on one or more nodes. 

> **Note:** A single process that handles installing and managing these internal Kubernetes components as processes on a server is often referred to as a Kubernetes **distribution**. Popular examples of such distributions are [KubeAdm](https://kubernetes.io/docs/reference/setup-tools/kubeadm/), [RKE](https://rancher.com/products/rke), [k3s](https://k3s.io/)/[RKE2](https://docs.rke2.io/). Distributions generally differ with respect to the way they manage those internal components; for example, RKE uses `Containers` on the host as the mechanism to manage the internal component processes themselves within the host while k3s/RKE2 deploy the internal Kubernetes components themselves as `Pods`.

Typically, creating a cluster involves first "installing" Kubernetes onto a etcd+controlplane node. This establishes the Kubernetes API Server, sets up the backing database (etcd) to store further transactions, and runs the default controllers. 

Once that is complete, you add additional worker or other nodes by "installing" Kubernetes on that node with a configuration that points it to the established API Server's endpoint (usually a DNS entry or IP address pointing to the controlplane node at the API Server's port, which is by default `:6443`).

> **Note:** While so far we have been describing `Nodes` as servers, it's important to call out that `Nodes` can be anything that can logically run the Kubernetes internal components as processes within it. Therefore, it is possible to use a single `Container` that runs these Kubernetes internal components as separate processes within its own sandbox (network namespace); this is precisely what [`k3d`](https://k3d.io) does with [`k3s`](https://k3s.io/)

> **Note:** With managed Kubernetes distributions (i.e. [`EKS`](https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html), [`GKE`](https://cloud.google.com/kubernetes-engine/), [`AKS`](https://docs.microsoft.com/en-us/azure/aks/), etc.) generally the etcd+controlplane nodes are already created and managed by the cloud provider for you. You only have the ability to add additional worker nodes, which you are responsible for managing.

## Next Up

Next, we will talk about [Kubernetes Clients](./01_clients.md)!