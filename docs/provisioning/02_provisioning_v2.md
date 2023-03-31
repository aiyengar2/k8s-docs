# Provisioning V2

This document outlines how Rancher implements CAPI to power its Provisioning V2 solution.

## A "Brief" Note On Rancher And CAPI

While Rancher's Provisioning V2 is **almost fully compliant** with upstream CAPI's **minimum** expectations of what Providers are expected to do today, it's important to understand the history of Rancher's support for provisioning Kubernetes clusters to understand why Rancher seems to be implementing the same providers in a slighly different way than upstream CAPI.

Specifically, one of the biggest differences between the way Rancher handles managing clusters and the way upstream CAPI generally handles it has to do with the difference between **provisioning + bootstrapping** Machines and **provisioning + managing** Machines.

### What is Bootstrapping?

The term "bootstrapping" comes from the phrase "to pull oneself by one's bootstraps". 

It refers to a self-starting process that continues and grows **without any user input**.

In the case of Kubernetes components installed by Kubernetes distributions, this applies since the Kubernetes components themselves are typically managed by some underlying daemon on the host (i.e. `systemd`, `Docker`, etc.) that differs depending on the Kubernetes distribution you are working with.

Therefore, once installed, the Kubernetes internal components are self-[re]starting processes that are capable of "pulling themselves by their bootstraps".

This is why the process of installing the Kubernetes distribution onto a node is typically referred to as "bootstrapping" a node.

### Bootstrapping v.s. Managing

It's important to distinguish between **bootstrapping** components, which is a **one-time** action on a node to start the self-healing processes, and **managing** components, which is a **continual** process that can receive user input to alter the behavior or configuration of the running self-healing processes.

This is the core of the difference between the approach to cluster provisioning that Rancher supports v.s. what upstream CAPI supports.

In upstream CAPI, you can only **bootstrap** new machines to add them onto an existing cluter. 

This is why, in the upstream CAPI world, `Machines` are immutable, `MachineDeployments` **replace** `Machines` instead of **re-configuring** the existing `Machine`, and "remediation" for failed `MachineHealthChecks` **delete** the unhealthy node (presumably to be replaced to satisfy the `MachineSet` requirements).

While this may work well in environments where you can assume 

however, this is not the case for Rancher's Provisioning V2 framework, which uses [`rancher/system-agent`](https://github.com/rancher/system-agent) to manage existing nodes without deleting them on changes to the cluster's configuration.
>
> On the other hand, Rancher supports both bootstrapping and managing existing nodes. This is discussed in more detail below as we outline the way Provisioning V2 actually works under the hood.
