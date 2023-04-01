# What is Provisioning V2?

Provisioning V2 is the set of controllers embedded into Rancher that implement its [RKE2](https://docs.rke2.io/) / [k3s](https://k3s.io/) cluster provisioning solution, powered by [CAPI](./00_capi.md).

## How Does Provisioning V2 Work?

To support Provisioning V2, Rancher directly embeds the upstream CAPI controllers into Rancher.

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
  - Running provisioning `Jobs` that execute [`rancher/machine`](https://github.com/rancher/machine) to provision and bootstrap
  - Supporting SSHing onto provisioned hosts after creation since it stores the host SSH keys that are returned from the provisioning `Job` as a Kubernetes Secret in the local / management cluster

### Managing Machines Instead Of "Re-Bootstrapping"

On updating the configuration of a CAPI-provisioned cluster, the normal CAPI strategy would be to **bootstrap** new machines and delete the old ones.

This is because upstream CAPI only supports **bootstrapping** a Machine, a **one-time** action on the machine to start the Kubernetes internal components with a specific configuration of each component.

This is why, in the upstream CAPI world:
- `Machine`s are immutable
- `MachineDeployment`s **replace** `Machine`s on modifications instead of **re-configuring** existing `Machine`s
- "Remediation" for failed `MachineHealthChecks` **delete** the unhealthy Machine (presumably to be replaced to satisfy the `MachineSet` requirements)
- "Remediation" for modifications to the cluster's control plane configuration **replaces** existing control plane `Machine`s with newly bootstrapped `Machine`s with the new control plane configuration

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

On the other hand, Rancher's Provisioning V2 supports **managing** a provisioned machine, a **continual** process where the Machine can receive user input to alter the behavior or configuration of the running Kubernetes components.

To do this, it utilizes [`rancher/system-agent`](https://github.com/rancher/system-agent), a daemon that is bootstrapped onto the physical server of the `Machine` and managed by `systemd` on Linux (or as a [Windows Service](https://learn.microsoft.com/en-us/dotnet/framework/windows-services/introduction-to-windows-service-applications) on Windows).

This daemon has `KUBECONFIG` that allows it to watch for a **"Machine Plan Secret"** in the local / management cluster.

The Machine Plan Secret is kept up-to-date by a special set of **RKE Planner** controllers that are part of the Provisioning V2 [Control Plane Provider](./01_capi_providers.md#control-plane-provider) implementation.

By updating the Machine Plan Secret, `rancher/system-agent` is informed about a **Plan** that needs to be executed on the node to reconcile the node against the new cluster configuration, which it then executes and reports back.

> **Note**: Just because Rancher manages the Kubernetes Internal Components does not mean it is breaking the CAPI Bootstrap Provider contract.
>
> If Rancher stopped managing the Machine the moment is was Ready, it would be identical to any other normal Bootstrap Provider in the upstream CAPI world; it just happens to be able to continue to pass on updates, partially due to the highly declarative design of RKE2 / K3s.

However, instead Rancher installs [`rancher/system-agent`](https://github.com/rancher/system-agent), a daemon that will sit on the Machine and listen to a "Machine Plan Secret" that allows Rancher to tell the machine how to modify itself to satisfy a new control plane configuration.










        - 
        - 
    - For those familiar with the analogy, this advantage should read as "Rancher supports both provisioning servers that need be treated as `pets` (i.e. hard to replace) as well as those that can be treated as `cattle` (i.e. can be easily swapped)"
- Airgapped clusters (clusters that are not exposed to the broader internet for incoming connections)

## A "Brief" Note On Rancher And CAPI

Rancher's Provisioning V2 is **almost fully compliant** with upstream CAPI's **minimum** expectations of what Providers are expected to do today.

However, it's important to understand that Rancher has had a history of supporting provisioning Kubernetes clusters (via its legacy Provisioning V1 solution) that influenced how it chose to design its CAPI providers for Provisioning V2.


### Bootstrapping v.s. Managing `Machine`s

