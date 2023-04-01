# What is Provisioning V2?

Provisioning V2 is the set of controllers embedded into Rancher that implement its [CAPI](./00_capi.md)-powered [RKE2](https://docs.rke2.io/) / [k3s](https://k3s.io/) provisioning solution.

## How Does Provisioning V2 Work?

In Provisioning V2, Rancher directly embeds the upstream CAPI controllers into Rancher.

Then, it defines a set of Provisioning V2's controllers that implement [all of the providers that CAPI supports](./01_capi_providers.md) and adds additional functionality that offers advantages over existing vanilla CAPI-provider solutions, such as providing support for the following features.

### Declarative Cluster Creation

Instead of running `clusterctl generate cluster` with command-line arguments and piping the output to `kubectl apply`, Rancher defines two custom resource definitions for creating clusters:
1. An `<Infrastructure>Config`
    - Also known as a **node template / machine pool configuration** for a particular infrastructure (like `DigitalOcean`)
    - Embeds the configuration that would be reflected in the `<Infrastructure>MachineTemplate`
    - Includes options that affect Kubernetes-distribution-level fields, such as whether this is an `etcd` / `controlplane` / `worker` node
    - Includes options that affect how the nodes in this pool are provisioned, such as whether to drain before delete, how to execute rolling updates, etc.)
2. A `provisioning.cattle.io` Cluster
    - Embeds one or more `<Infrastructure>Configs` under its `.spec.rkeConfig.machinePools`
    - Embeds the desired configuration of [RKE2](https://docs.rke2.io/) / [k3s](https://k3s.io/) under the other `.spec.rkeConfig.*` fields

On simply creating a `provisioning.cattle.io` Cluster that has a valid Machine Pool configuration, all the other CAPI resources that would be contained in the manifest are created, updated, and removed along with it.

### Generic Machine Provider

Unlike most other CAPI Machine Providers, Rancher implements a **generic Machine Provider** that supports deploying infrastructure to any of the providers of infrastructures that have [Node Drivers](https://github.com/rancher/machine/tree/master/drivers) supported by [`rancher/machine`](https://github.com/rancher/machine).

This includes:
  - Dynamically creating and implementing CRDs for `<Infrastructure>Config`s, `<Infrastructure>MachineTemplate`s, and `<Infrastructure>Machine`s on registering a new Node Driver
  - Running provisioning `Jobs` that execute [`rancher/machine`](https://github.com/rancher/machine) to provision and bootstrap new servers
  - Supporting SSHing onto provisioned hosts after creation using host SSH keys returned by the provisioning `Job`

### Managing Machines Instead Of "Re-Bootstrapping"

On updating the configuration of a CAPI-provisioned cluster, the normal CAPI strategy would be to **bootstrap** new machines and delete the old ones.

This is because upstream CAPI only supports **bootstrapping** a Machine, a **one-time** action on the machine to start the Kubernetes internal components with a specific configuration of each component.

> **Note**: Why is this called "bootstrapping"?
>
> The term "bootstrapping" comes from the phrase "to pull oneself by one's bootstraps". 
>
> It refers to a self-starting process that continues and grows **without any user input**.
>
> In the case of Kubernetes components installed by Kubernetes distributions, this applies since the Kubernetes components themselves are typically managed by some underlying daemon on the host (i.e. `systemd`, `Docker`, etc.) that differs depending on the Kubernetes distribution you are working with.
>
> Therefore, once installed, the Kubernetes internal components are self-[re]starting processes that are capable of "pulling themselves by their bootstraps".
>
> This is why the process of installing the Kubernetes distribution onto a node is typically referred to as "bootstrapping" a node.

This is why, in the upstream CAPI world:
- `Machine`s are immutable
- `MachineDeployment`s **replace** `Machine`s on modifications instead of **re-configuring** existing `Machine`s
- "Remediation" for failed `MachineHealthChecks` **delete** the unhealthy Machine (presumably to be replaced to satisfy the `MachineSet` requirements)
- "Remediation" for modifications to the cluster's control plane configuration **replaces** existing control plane `Machine`s with newly bootstrapped `Machine`s with the new control plane configuration

On the other hand, Rancher's Provisioning V2 supports **managing** a provisioned machine, a **continual** process where the Machine can receive user input to alter the behavior or configuration of the running Kubernetes components.

To do this, it utilizes [`rancher/system-agent`](https://github.com/rancher/system-agent), a daemon that is bootstrapped onto the physical server of the `Machine` and managed by `systemd` on Linux (or as a [Windows Service](https://learn.microsoft.com/en-us/dotnet/framework/windows-services/introduction-to-windows-service-applications) on Windows).

This daemon has `KUBECONFIG` that allows it to watch for a **"Machine Plan Secret"** in the local / management cluster.

The Machine Plan Secret is kept up-to-date by a special set of **RKE Planner** controllers that are part of the Provisioning V2 [Control Plane Provider](./01_capi_providers.md#control-plane-provider) implementation.

By updating the Machine Plan Secret, `rancher/system-agent` is informed about a **Plan** that needs to be executed on the node to reconcile the node against the new cluster configuration, which it then executes and reports back via the same Machine Plan Secret.

> **Note**: Just because Rancher manages the Kubernetes Internal Components does not mean it is breaking the CAPI Bootstrap Provider contract.
>
> If Rancher stopped managing the Machine the moment is was Ready, it would be identical to any other normal Bootstrap Provider in the upstream CAPI world; it just happens to be able to continue to pass on updates, partially due to the highly declarative design of RKE2 / K3s.

> **Note**: For those familiar with the analogy, the primary advantage of managing servers as opposed to replacing them is tht Rancher supports both provisioning servers that need be treated as "pets" (i.e. hard to replace) as well as those that can be treated as "cattle" (i.e. can be easily swapped).

#### "Air-gapped" Downstream Clusters

An "air-gapped" cluster is a cluster that is not advertised or accessible to **incoming** connections, primarily for security purposes.

To support generating a `KUBECONFIG` that can be used to send requests to this "air-gapped" cluster, Rancher deploys components onto the downstream cluster that contain a **reverse tunnel client** powered by a [`rancher/remotedialer`](https://github.com/rancher/remotedialer), a Layer 4 TCP Remote Tunnel Dialer.

On the downstream cluster being fully provisioned, this deployed client registers with Rancher running in the local / management cluster (which hosts a **reverse tunnel server** at a registration endpoint in its API).

On a downstream cluster registering with Rancher, Rancher can expose an endpoint that allows access to the downstream API provided that a user has a valid **Rancher authentication token** that grants it permission to access the downstream cluster by impersonating some user in that cluster.

This endpoint and the user's Rancher authentication token are then directly used to define `KUBECONFIG` that the user can use to communicate with the downstream, air-gapped cluster via Rancher.
