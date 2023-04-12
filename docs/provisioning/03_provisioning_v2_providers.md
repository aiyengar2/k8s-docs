# Provisioning V2 Providers

This document does a deep-dive into how Provisioning V2 implements each of the providers that CAPI expects a third-party to implement to provision a cluster.

In Rancher, all the Provider controllers exist under `pkg/controllers/provisioningv2`, so every path referenced in this doc will be relative to that path.

Init
- `rke2/provisioningcluster`
- `rke2/provisioninglog`

Cluster
- `rke2/rkecluster`

Bootstrap
- `rke2/bootstrap`

Machine
- `rke2/dynamicschema`
- `rke2/machineprovision`
- `rke2/unmanaged`
- `rke2/machinenodelookup`: seems to be updating `.status.address` and `.spec.providerId` on `<Infrastructure>Machine` objects tied to `Machine`s tied to `RKEBootstrap`s, used for `CustomMachine`s

ControlPlane
- `rke2/machinedrain`
- `rke2/planner`
- `rke2/plansecret`

Fleet
- `fleetcluster`
- `fleetworkspace`

SUC-based Partial Takeover
- `managedchart`
- `rke2/managesystemagent`

Legacy
- `cluster`

Cloud Credentials
- `rke2/secret`


## (Cluster) Infrastructure Provider

TBD

## Bootstrap Provider

TBD

## Machine (Infrastructure) Provider

TBD

## Control Plane Provider

TBD

## Next Up

Next, we'll do a walkthrough of [Provisioning V2](./04_walkthrough.md) in a live cluster!
