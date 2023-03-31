# Provisioning V2 x CAPI

This document outlines how Rancher implements CAPI to power its Provisioning V2 solution.

## A "Brief" Note On Rancher And CAPI

While Rancher's Provisioning V2 is **almost fully compliant** with upstream CAPI's **minimum** expectations of what Providers are expected to do today, it's important to understand the history of Rancher's support for provisioning Kubernetes clusters to understand why Rancher seems to be implementing the same providers in a slighly different way than upstream CAPI.

Specifically, one of the biggest differences between the way Rancher handles managing clusters and the way upstream CAPI handles managing clusters has to do with the difference between **provisioning + bootstrapping** Machines and **provisioning + managing** Machines.

### What is Bootstrapping?

The term "bootstrapping" comes from the phrase "to pull oneself by one's bootstraps". 

It refers to a self-starting process that continues and grows **without any user input**.

In the case of Kubernetes components installed by Kubernetes distributions, this applies since the Kubernetes components themselves are typically managed by some underlying daemon on the host (i.e. `systemd`, `Docker`, etc.) that differs depending on the Kubernetes distribution you are working with.

Therefore, once installed, the Kubernetes internal components are self-[re]starting processes that are capable of "pulling themselves by their bootstraps".

This is why the process of installing the Kubernetes distribution onto a node is typically referred to as "bootstrapping" a node.

### Bootstrapping Machines v.s. Managing Machines

**Bootstrapping** a machine is a **one-time** action on the machine to start the self-healing processes. 

**This is what upstream CAPI supports**.

This is why, in the upstream CAPI world:
- `Machines` are immutable
- `MachineDeployments` **replace** `Machines` instead of **re-configuring** the existing `Machine`
- "Remediation" for failed `MachineHealthChecks` **delete** the unhealthy Machine (presumably to be replaced to satisfy the `MachineSet` requirements)

On the other hand, **managing** the mMchine is a **continual** process where the Machine can receive user input to alter the behavior or configuration of the running self-healing processes.

**This is what Rancher's Provisioning V2 supports**

If Rancher stopped managing the Machine the moment is was Ready, it would be identical to any other normal Bootstrap Provider in the upstream CAPI world.

However, instead Rancher installs [`rancher/system-agent`](https://github.com/rancher/system-agent), a daemon that will sit on the Machine and listen to a "Machine Plan Secret" that allows Rancher to tell the machine how to modify itself to satisfy a new control plane configuration.
