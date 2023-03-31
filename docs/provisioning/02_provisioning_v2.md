# Provisioning V2 x CAPI

This document outlines how Rancher implements CAPI to power its Provisioning V2 solution.

## A "Brief" Note On Rancher And CAPI

While Rancher's Provisioning V2 is **almost fully compliant** with upstream CAPI's **minimum** expectations of what Providers are expected to do today, it's important to understand that Rancher has had a history of supporting provisioning Kubernetes clusters (via its legacy Provisioning V1 solution) that influenced how it chose to make design decisions around the way it implemented its CAPI providers for Provisioning V2.

### Bootstrapping v.s. Managing `Machine`s

Upstream CAPI only supports **bootstrapping** a Machine is a **one-time** action on the machine to start the Kubernetes internal components with a specific configuration on a Machine. 

> **Note**: What is "bootstrapping"?
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
- `MachineDeployment`s **replace** `Machine`s instead of **re-configuring** the existing `Machine`
- "Remediation" for failed `MachineHealthChecks` **delete** the unhealthy Machine (presumably to be replaced to satisfy the `MachineSet` requirements)
- "Remediation" for modifications to the cluster's control plane configuration **replaces** existing control plane `Machine`s

On the other hand, **managing** the mMchine is a **continual** process where the Machine can receive user input to alter the behavior or configuration of the running self-healing processes.

**This is what Rancher's Provisioning V2 supports**

If Rancher stopped managing the Machine the moment is was Ready, it would be identical to any other normal Bootstrap Provider in the upstream CAPI world.

However, instead Rancher installs [`rancher/system-agent`](https://github.com/rancher/system-agent), a daemon that will sit on the Machine and listen to a "Machine Plan Secret" that allows Rancher to tell the machine how to modify itself to satisfy a new control plane configuration.