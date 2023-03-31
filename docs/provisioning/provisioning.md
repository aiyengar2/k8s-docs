# Provisioning V2

## What is CAPI (Cluster API)?


> **Note**: Rancher's Provisioning V2 is **not CAPI**; it is considered to be "CAPI-driven", which means that while it uses CAPI's controllers (which are embedded directly into Rancher) to **initially** drive the provisioning of nodes and clusters, it handles features like upgrading existing nodes and clusters for a new configuration (e.g. a new Kubernetes version) in a completely different way that upstream CAPI does once that initial process has taken place.
>
> More on that below!

## What is Provisioning V2?

As mentioned [in the note above](#what-is-capi-cluster-api), Rancher's Provisioning V2 framework is not strictly CAPI; it's considered to be a **"CAPI-driven" framework**, which means that it uses the same underlying embedded CAPI controllers but implements some of the building blocks of CAPI (i.e. Infrastructure Providers and Bootstrap Providers) in a way that is not in-line with upstream expectations.

Also unlike normal CAPI, users **should not** directly interact with the embedded CAPI controllers by creating CAPI CRs (like `Clusters`, `MachineDeployments`, `MachineSets`, and `Machines`) or by directly creating the Rancher CAPI Provider CRs (like `RKECluster`, `RKEControlPlane`, `<Infrastructure>Machine`s, and `<Infrastructure>MachineTemplate`s).

Instead, users are expected to just create one or more `<Infrastructure>Config`s (i.e. `DigitalOceanConfig`, `AzureConfig`, etc.) and reference them in a single `provisioning.cattle.io` Cluster CR's `.spec.rkeConfig.machinePools[*].machineConfigRef`. 

> **Note**: For more information on what Machine Pools are (as referenced in `.spec.rkeConfig.machinePools`), [see the section below](#rancher-machine-pools).

On creating the Cluster CR pointing to valid `<Infrastructure>Config`s, the Rancher controllers will automatically handle configuring the CAPI CRs and CAPI Provider CRs on the user's behalf. It does this by treating the other CRs as **"child" resources** that are applied, patched, and deleted based on the "parent" Provisioning V2 Cluster CR's current configuration.

To see a concrete example of this, please check out the resources shown in the [walkthrough](./walkthrough.md)!

> **Note**: The [`apply` module of `rancher/wrangler`](https://github.com/rancher/wrangler/tree/master/pkg/apply) is how Rancher achieves creating and managing "child" objects from a single "parent" object.
>
> Essentially, a single "parent" object declares a `desiredSet` of resources that should be tied to it. The objects in this `desiredSet` are the expected "child" objects for this "parent".
>
> On applying a `desiredSet`, Rancher will utilize annotations on the object to identify it as part of this `desiredSet`. This will later be used to handle reconcile logic on the next apply.
>
> On running the `Apply` operation on that "parent" object with a set of new objects:
> - Objects in the cluster under the old `desiredSet` but not in the new `desiredSet` are **deleted**
> - Objects in the `desiredSet` but not in the cluster under the old `desiredSet` are **created**
> - Objects in both the cluster and the new `desiredSet` are **patched**, if necessary
>
> To run commands to see what `desiredSets` are in your cluster, please see the Bash functions defined [here](./walkthrough.md#utility-functions).

> **Note**: Why does apply using annotations instead of [Owner References](https://kubernetes.io/docs/concepts/overview/working-with-objects/owners-dependents/)?
>
> Owner References requires the dependent object to be within the same namespace, but apply can be used to manage child objects across namespaces (or even to manage child resources that are non-namespaced / global).

### Rancher Machine Pools

When defining the overall Cluster object, Rancher expects users to define one or more Machine Pools that each represent a different subset of nodes in your cluster that **all have the same node-level configuration** (identified by the `<Infrastructure>Config` CR referenced by the Machine Pool).

For example, you may want to have a cluster with exactly one Machine Pool whose Machines take on all of the Kubernetes roles (`controlplane`, `etcd`, `worker`); in this case, the nodes in your cluster will be homogeneous since they will be based on the same underlying node configuration (`<Infrastructure>Config`) passed onto the infrastructure provider you are using to provision these nodes (via the `<Infrastructure>MachineTemplate` tied to the Machine Pool that was created off of its `<Infrastructure>Config`).

On the other hand, you may want to have a cluster with a subset of `controlplane` / `etcd` nodes and a different subset of dedicated `worker` nodes; in this case, you would create two Machine Pools in this cluster, which can be done by modifying the existing Machine Pools in the `provisioning.cattle.io` Cluster CR.

In this same cluster, you may now want to add a new pool of `worker` nodes that have larger CPU / Memory sizes for specific large workloads; in this case, you would add another Machine Pool to your existing cluster, which can be done by adding a new Machine Pool to the `provisioning.cattle.io` Cluster CR.

> **Note**: Rancher Machine Pools are **have nothing to do with** (currently) experimental [CAPI Machine Pools](https://cluster-api.sigs.k8s.io/tasks/experimental-features/machine-pools.html), which are **not currently implemented by Rancher**.

### Rancher's Generic Infrastructure Provider

Unlike in upstream CAPI, where the expectation is that each infrastructure provider is independently deployed and is tied to a specific infrastructure, Rancher implements a **generic infrastructure provider** that handles managing infrastructure across multiple actual providers of infrastructure, powered by [rancher/machine](https://github.com/rancher/machine).

> **Note**: Another way of thinking of Rancher is as a "meta-infrastructure provider"; a provider of infrastructure providers (called **Node Drivers** in Rancher) that all share the same underlying controllers but individually do the provisioning for each infrastructure by leveraging the driver-specific provisioning logic in [rancher/machine](https://github.com/rancher/machine).

#### What is `rancher/machine`?

`rancher/machine` is a fork of [docker/machine](https://github.com/docker/machine) that Rancher has been maintaining since the upstream repository has been archived.

It can be used as an independent binary of its own right; each call to `create` like `/path/to/binary/rancher-machine create -d <supported-driver-name> <supported-driver-create-args>` can be used to provision exactly one node on a given infrastructure (identified by `<supported-driver-name>`), given some configuration arguments for the node (identified within the `<supported-driver-create-args>`).

#### How does Provisioning V2 use `rancher/machine` to create Infrastructure Provider CRDs?

On Rancher's startup, Rancher encodes the specific list of drivers from `rancher/machine` it supports by creating the corresponding `NodeDriver` CRs in the management cluster. 

These `NodeDriver` CRs primarily contain the driver's name, some metadata fields, and some small options unrelated to `rancher/machine`.

On seeing a `NodeDriver` CR be created, Rancher's controllers automatically create a `DynamicSchema` CR that is created by grabbing the driver name from the `NodeDriver` CR and making a [Remote Procedure Call](https://en.wikipedia.org/wiki/Remote_procedure_call) to `rancher/machine` to get the create flags for that specific driver.

> **Note**: This Remote Procedure Call relies on the `rancher/machine`'s binary being embedded into a specific path in Rancher's container image so that it can make this call; this is why Rancher's Dockerfile downloads the `rancher/machine` binary on building a Rancher container image. 
>
> If you are running Rancher locally, you will also need to ensure this binary exists in that path to ensure that Rancher is able to make thie Remote Procedure Call.

These create flags are then directly converted into the `DynamicSchema` CR's spec fields and persisted into the cluster.

Finally, on seeing the creation of a `DynamicSchema` CR, Provisioning V2 controllers kick in to automatically convert a `DynamicSchema` into a  `<Infrastructure>Config` CRD that serves as the Infrastructure Provider CRD for that driver!

> **Note**: Why do we convert to `NodeDriver` and then to `DynamicSchema` instead of directly creating the CRDs?
>
> `NodeDrivers` are an essential part of Rancher's Provisioning V1 solution used to create [RKE](https://www.rancher.com/products/rke), Rancher's legacy Kubernetes distribution that has been replaced by `k3s` / `RKE2`.
>
> Therefore, to avoid duplicated code, we directly create `DynamicSchema`s on seeing `NodeDrivers` be created.

#### How does Provisioning V2 use `rancher/machine` to provision infrastructure?

We know that the spec of the `<Infrastructure>Config` exactly matches the arguments that `rancher/machine` expects to provision a node in that infrastructure.

We also know that the spec of the `<Infrastructure>Config` exactly matches what will end up in the `<Infrastructure>Machine`.

Therefore, provisioning a node in Provisioning V2 simply results in Rancher creating a **Job** that runs `rancher/machine` after translating the contents of the `<Infrastructure>Machine` into command line arguments for the `rancher/machine` binary.

Once that Job is completed (or if it fails), we can update the `<Infrastructure>Machine` with the appropriate status.

> **Note**: The machine image is defined in the Rancher environment variable `CATTLE_MACHINE_PROVISION_IMAGE`, which is also a Rancher setting that can be modified after spinning up Rancher.

> **Note**: Are we packaging `rancher/machine` twice?
>
> Yes, the `rancher/machine` binary is being packaged as a **binary** at a path in your Rancher container image to translate driver options into CRDs and as an image provided to Rancher to run `rancher/machine` provisioning Jobs. 
>
> This means that while you may be able to test fixes to provisioning logic by updating `rancher/machine` out-of-band on an existing Rancher installation, you will need to rebuild the Rancher container image if your fixes into `rancher/machine` involve adding new fields to the drivers for it.

#### How does Provisioning V2 support SSHing into Machines?

While normal CAPI doesn't necessarily specify that Infrastructure Providers are supposed to support actions like SSHing into nodes, Rancher supports SSHing into provisioned nodes via the [`rancher/steve`](https://github.com/rancher/steve) API hosted by Rancher to access the downstream Kubernetes cluster's API.

The Rancher Infrastructure Provider supports this with two actions:
1. It creates the Secret with no contents in `pkg/controllers/provisioningv2/rke2/machineprovision` by a **direct apply**; as a result, the object set ID for this apply action is `""`, not filled in like when an apply is performed via a `*GeneratingHandler`
2. It supplies `--secret-name` and `--secret-namespace` (equivalent to name and namespace of the above Secret) as arguments to the `rancher/machine` Pod on provisioning, which results in `rancher/machine` using a Kubernetes Secret client to update that secret to contain all the state information it emits on a successful provision, which includes things like the IP address of the node.

As a result, on receiving an API request to SSH into a node, Rancher is able to query this `machine-state` Secret to figure out how to perform an SSH request into the target node (such as identifying the IP address that can be used to run the SSH command).

This `machine-state` Secret is expected to live for as long as the Machine does and should not be deleted.

### Rancher's System Agent "Bootstrap" Provider

#### What does Rancher bootstrap onto the provisioned machines?

Unlike in upstream CAPI, where the expectation is that each bootstrap provider generally **directly** installs [the relevant Kubernetes components per node](../controllers/00_introduction.md#what-does-it-mean-to-install-kubernetes-onto-a-set-of-servers), Rancher simply installs [`rancher/system-agent`](https://github.com/rancher/system-agent) onto the node as a [systemd](https://systemd.io/) Service with a `KUBECONFIG` that allows the node to communicate with the Rancher management cluster.

#### How does Rancher bootstrap provisioned machines?

It installs `rancher/system-agent` by supplying the Infrastructure Provider with a Secret (via the `RKEBootstrap`s `.status.dataSecretName`) that contains the [`install.sh` found in the `rancher/system-agent` repo](https://github.com/rancher/system-agent/blob/main/install.sh)). It is the Infrastructure Provider's responsibility to execute the script that is provided in this way by the Bootstrap Provider.

> **Note**: For Windows, it supplies the [`install.ps1` found in the `rancher/wins` repo](https://github.com/rancher/wins/blob/main/install.ps1) to the Secret instead, since `rancher/wins` directly embeds the `rancher/system-agent` within it.

The install script will perform the following three actions:
- Validate the CA certificates provided to the script
- Make a request to the provided server url (expected to be Rancher's URL) to get the connection information for this machine, which will include the `KUBECONFIG` that allows the node to communicate with the Rancher management cluster
- Install [`rancher/system-agent`](https://github.com/rancher/system-agent) onto the node as a [systemd](https://systemd.io/) Service, utilizing the `KUBECONFIG` from the previous step, which will configure `rancher/system-agent` to start watching the `machine-plan` Secret

> **Note**: Why deploy `rancher/system-agent` as a [systemd](https://systemd.io/) Service?
>
> This ensures that, if `rancher/system-agent` goes down for some reason (i.e. the node is rebooted), it is automatically restarted without any intervention from Rancher's Bootstrap Provider itself.
>
> This is important since, as mentioned before, a Bootstrap Provider is only expected to be involved up till a node is provisioned and added to a Kubernetes cluster; from there, it's not expected that the Bootstrap Provider should do anything for a node that is already provisioned.
>
> The only thing that CAPI supports after a node has been provisioned is `MachineHealthChecks`, which are implemented by CAPI's own controllers, not a provider's controllers.

The `KUBECONFIG` is used by the `rancher/system-agent` to watch for a **Machine Plan Secret** in the management cluster, which will contain something like the `*.plan` file(s) in [the `rancher/system-agent` examples](https://github.com/rancher/system-agent/tree/main/examples); on seeing an update to the Secret, `rancher/system-agent` executes the Plan, which actually does the work to create or configure the underlying Kubernetes components.

The provided plans usually just involve creating some files and running a single image, which is either the [RKE2 System Agent Installer](https://github.com/rancher/system-agent-installer-rke2) or [K3s System Agent Installer](https://github.com/rancher/system-agent-installer-k3s), depending on which type of cluster you would like to provision. 

This image itself typically just runs the underlying `k3s` or `rke2` binary the same way that users are instructed to do so to manually provision those clusters in the docs; this logic is encoded in each repository's `run.sh` file.

### How does Rancher connect to the downstream cluster's control plane?

Unlike in upstream CAPI, where it is expected that each provisioned downstream Kubernetes cluster has to have a **publicly accessible control plane endpoint** (or at least one that is accessible by the management cluster) to generate a `KUBECONFIG` for to access the downstream cluster, Rancher only expects that the management cluster has to have a **either a public URL or a URL that is accessible to all downstream cluster machines** (i.e. the Rancher URL).

> **Note**: Why is this detail important to Rancher's provisioning?
>
> Because Rancher only needs the management cluster to be accessible to all downstream clusters, Rancher can support a special class of clusters called **airgapped** clusters: clusters that are not connected to the external internet for **in-bound** requests, primarily for security purposes.
>
> Instead, these clusters can reach out to Rancher to establish the connection, which then allows packets to only be transmitted to the downstream cluster through that narrow pipe.

This is because Rancher has a fundamentally different way of communicating from a management cluster to a downstream cluster, powered by [`rancher/remotedialer`](https://github.com/rancher/remotedialer), a **Layer 4** HTTP reverse proxy tunnnel.

This works by having the downstream cluster deploy a Rancher agent, which will run a `rancher/remotedialer` Client; on startup, that Client will reach out to the `rancher/remotedialer` Server hosted in the main Rancher instance running in the management cluster (which is expected to be accessible via the Rancher URL from the machine), which will allow the management cluster to forward received packets to the downstream cluster.

This is why Rancher sets all control plane endpoints on the `RKECluster` to `localhost:6443` by default, since it's never expected for a user to directly communicate with the downstream cluster without going through Rancher's API, 

Also, instead of having a normal `KUBECONFIG`, a `KUBECONFIG` that is generated by Rancher looks something like this:

```yaml
apiVersion: v1
kind: Config
clusters:
- name: "my-cluster"
  cluster:
    server: "https://<RANCHER_URL>/k8s/clusters/c-m-<cluster-id>"
    certificate-authority-data: <some-ca-data>

users:
- name: "my-cluster"
  user:
    token: "kubeconfig-user-<identifier>:<token>"

...
```

In the above `KUBECONFIG`, `kubeconfig-user-<identifier>:<token>` represents a **Rancher API Token**, which is used to authenticate the user and figure out the user's underlying token in the downstream cluster, and `/k8s/clusters/c-m-<cluster-id>` is the Rancher API path that goes to the Kubernetes API (powered by [`rancher/steve`](https://github.com/rancher/steve)) of the downstream cluster identified by the cluster ID `c-m-<cluster-id>`.

## Provisioning V2 Workflow

On a high-level, here's what happens when you create a Kubernetes cluster using Provisioning V2.

For a more hands-on walkthrough, check out the [other doc](./walkthrough.md).

### Stage 1: Configure and apply `provisioning.cattle.io` Cluster

This step is normally **executed by the user on the Rancher UI** when they try to create or modify an RKE / K3s cluster on the Rancher UI with a given infrastructure provider (i.e. `DigitalOcean`)

#### For Rancher-Provisioned Clusters

The user will normally specify one or more Machine Pools, which will be filled out via a form that reflects the fields in the underlying `<Infrastructure>Config` (i.e. you will be able to specify the `size` for the Digitial Ocean Nodes of this machine pool at this step). You will need at least one `controlplane`, `etcd`, and `worker` Machine Pool to be specified.

After that, users will be provided a series of options around the cluster's configuration (i.e. what Kubernetes version they would like to deploy) that end up in the `.spec.rkeConfig` of the Cluster object, which identifies the k3s/RKE2 settings that they would like to supply to bootstrap each controlplane node with the required configurations.

On hitting the Create button for the cluster:
- Each Machine Pool specified here will have its configuration land in a `<Infrastructure>Config` CR that is created or updated by the UI
- The Cluster object will be created with those Machine Pools and the RKE Config provided

> **Note**: This can also be manually done, such as if a user wants to use another piece of automation to handle spinning up the cluster instead of using the Rancher UI like Terraform, but the user will also be expected to manually apply the `<Infrastructure>Config` object(s) themselves for each Machine Pool they would have declared on the UI before applying the Cluster object.

### Stage 2: `rke-cluster` Controller creates child objects

On seeing the `provisioning.cattle.io` Cluster and `<Infrastructure>Config`(s) be persisted, the `rke-cluster` controller that is tied to a `RegisterClusterGeneratingHandler` call (currently under `pkg/controllers/provisioningv2/rke2/provisioningcluster`) will be triggered.

This will create all the child CAPI, Infrastructure Provider, and Bootstrap Provider CRs that are outlined in [the walkthrough](./walkthrough.md).

> **Note**: What is a `*GeneratingHandler`?
>
> As Rancher uses [`rancher/wrangler`](https://github.com/rancher/wrangler) as its underlying controller framework, **as opposed to upstream's [`kubernetes-sigs/kubebuilder`](https://github.com/kubernetes-sigs/kubebuilder)**, Wrangler supports this unique type of `OnChange` / `Reconcile` handler whose signature returns three things: the list of child objects associated with the parent object that is being reconciled that need to be **generated** on the parent object's configuration changing (which is why it is called a **Generating** handler), the updated status of the parent object, and an error.
>
> Under the hood, what it actually does is configure a `wrangler.Apply` to treat the parent object that is being reconciled as the owner of a `desiredSet` that has the same name as the GeneratingHandler's handler name.
>
> This is why you can identify which controller created the `wrangler.Apply` child resources since the name of the handler will exactly match the value of the annotation `objectset.rio.cattle.io/id` on the child resource).
>
> For example, in this step the `GeneratingHandler`'s name is `rke-cluster`, so every child object created by this controller will have the annotation `objectset.rio.cattle.io/id: rke-cluster`.
>
> You'll see these types of handlers as a common pattern in the Provisioning V2 code since it's used any time this type of "parent" and "child" model for resources makes sense.
>
> Another unique type of handler you will see is `relatedresource.Watch`, which allows you to ensure that triggering an `OnChange` operation of any watched resource (i.e. a "child" resource) causes the enqueued type (the type of the "parent" resource) to get re-enqueued by the controllers.
>
> Therefore, another common pattern in the Provisioning V2 code is to set up a `relatedresource.Watch` that enqueues the "parent" `provisioning.cattle.io` Cluster object on seeing a modified "child" object (i.e. `RKECluster`), which ensures that a modification to the "child" is always overridden by the configuration that the "parent" expects of that child.

### Stage 3: CAPI Controller creates child objects

On seeing the `MachineDeployment` that is tied to a `RKEBootstrapTemplate` and `<Infrastructure>MachineTemplate` that were all created as child objects of the `provisioning.cattle.io` Cluster, the CAPI controllers will try to create the `Machine` objects necessary based on the spec.

To do this, it will first create a `MachineSet` tied to the `MachineDeployment` that represents the **immutable**, current configuration of the `MachineDeployment` before the CAPI controller starts to create `Machines`.

> **Note**: This is necessary since, if you were to modify the `MachineDeployment` while `Machines` were being provisioned, CAPI could end up in a race condition around how it configures those `Machines`. This is prevented by having an immutable `MachineSet` be in the middle.

Once the `MachineSet` is created, CAPI will automatically create two objects per `Machine`:
- The `RKEBootstrap` , which is configured using the `RKEBootstrapTemplate` tied to the `MachineDeployment`
- The `<Infrastructure>Machine`, which is configured using the `<Infrastructure>MachineTemplate` tied to the `MachineDeployment`

Since these are two CRDs implemented by the Rancher controllers, we will "hand-off" the processing back to Rancher in the next step.

### Stage 4: Rancher Bootstrap Provider creates `bootstrap` and `machine-plan` Secrets

On seeing the `RKEBootstrap` CR per machine, the `rke-bootstrap` controller that is tied to a `RegisterRKEBootstrapGeneratingHandler` call (currently under `pkg/controllers/provisioningv2/rke2/bootstrap`) will be triggered.

This will create all the child Secrets and RBAC resources of the `RKEBootstrap` CR that are outlined in [the walkthrough](./walkthrough.md) **per `Machine`**, including:
- The `bootstrap` Secret, which will be created with the `cloud-init` script necessary to install `rancher/system-agent` onto the node. This secret is ephemeral and will be deleted once the `Machine` is provisioned
- The `machine-plan`, which will initially contain nothing within it

### Stage 5: RKE2 Planner fills in `machine-plan` Secret

Once the `machine-plan` Secret has been created, the RKE2 Planner controllers will start to reconcile against the Secret.

#### `plansecret` Controller

On seeing the `machine-plan` Secret, the `plansecret` controller will convert the Secret into a `*plan.Node`

#### `machinedrain` Controller

contains the expected plan (configuration) for `rancher/system-agent` process running on each machine. This secret will always exist for every `Machine` managed by your management cluster, is kept up-to-date by Rancher controllers watching the `RKEControlPlane` CR for the cluster, and is constantly watched by the `rancher/system-agent` running on the Node

### Stage 6: Rancher Infrastructure Provider provisions and bootstraps machines

On seeing the creation of the `<Infrastructure>Machine`, Rancher will translate the `.spec` of the `<Infrastructure>Machine` into arguments for a [`rancher/machine`](https://github.com/rancher/machine) Job, [as described above](#how-does-provisioning-v2-use-ranchermachine-to-provision-infrastructure).

The `.spec.bootstrap.configRef` that points to the `RKEBootstrapTemplate` will be translated by directly copying the value of `.status.dataSecretName` (which points to the `bootstrap` Secret) on the `RKEBootstrapTemplate` into a [Secret Volume](https://kubernetes.io/docs/concepts/storage/volumes/#secret) mounted on the provisioning Job under `/run/secrets/machine`.

This path (specifically `/run/secrets/machine/value`) is then passed in as the `--custom-install-script` path.

It will also create an empty `machine-state` Secret and pass in the relevant command line argments to ensure the `rancher/machine` Job fills it in on a succesful invocation.

On completion of this Job, a `Machine` will have been **provisioned and bootstrapped**.

As discussed [before](#how-does-provisioning-v2-support-sshing-into-machines), the `rancher/machine` Job will also end up filling in the empty `machine-state` Secret, leaving behind the information necessary for Rancher to SSH into nodes after-the-fact.

Also, as discussed [before](#ranchers-system-agent-bootstrap-provider), a bootstrapped machine will have `rancher/system-agent` running on the node as a systemd Service, which will run the plan created for this node and stored in the `machine-plan` Secret in the previous stage.

### Stage 7: `rancher/system-agent` reconciles Plan from `machine-plan` Secret and updates Secret

### Stage 8: RKE2 Planner updates `RKECluster` Conditions, which updates CAPI `Cluster`

### Stage 9: Rancher installs add-on charts

Rancher installs `fleet-agent` onto the downstream cluster, which follows the ["Manager-Initiated" Registration Process](https://rancher.github.io/fleet/cluster-overview/#manager-initiated-registration) to register the `fleet-agent` with the main `fleet` instance running in the management cluster.

> **Note**: Why does Provisioning V2 need to create a `fleet-agent`?
>
> Fleet is used as the underlying deployment mechanism for `ManagedCharts`, a type of CR that represents a chart that needs to be deployed and kept up-to-date on a downstream cluster by Fleet.
>
> It should be noted that Fleet will not watch the resources deployed within this chart but will override changes to deployed resources from this chart on an upgrade.

Once the downstream cluster has Fleet installed, Rancher creates a `ManagedChart` for `rancher/system-upgrade-controller` (SUC), which ensures that the `rancher/syste-=upgrade-controller` chart is installed onto the downstream cluster.

Then, Rancher creates a `ManagedChart` for the `rancher/system-agent` SUC `Plan`, which will be picked up by the `rancher/system-upgrade-controller` running in the cluster. This will ensure `rancher/system-agent` is kept up-to-date on all nodes, such as in the case of a Rancher upgrade with a new `rancher/system-agent` version.

> **Note**: Why can't Provisioning V2 use `rancher/system-agent` to update itself?
>
> In theory, this is possible; however, `rancher/system-upgrade-controller` has better configuration options around executing upgrades to system components **across nodes** in a Kubernetes cluster, whereas `rancher/system-agent` only considers the node it is running on.
>
> For example, with `rancher/system-upgrade-controller` you can choose to execute the upgrade of `rancher/system-agent` as a **rolling upgrade** across your cluster with a single Plan; this wouldn't be possible with `rancher/system-agent`.

## Provisioning V2 Workflow For Special Clusters

### Custom Clusters

A Custom Cluster in Rancher is a set of already-provisioned nodes that require Rancher to logically glue them together into a Kubernetes cluster via installing k3s / RKE2 onto the nodes.

In this case, users will still be provided a series of options around the cluster's configuration as described above; however, on creating the cluster, **no Machine Pools will be specified**.

Instead, users are expected to run a command on **each** of the nodes that will contain a registration token and an auto-generated machine ID. This registration command looks something like this:

```bash
curl -fL https://<RANCHER_URL>/system-agent-install.sh | sudo  sh -s - --server https://<RANCHER_URL> --label 'cattle.io/os=linux' --token <SOME_TOKEN> --ca-checksum <SOME_CHECKSUM> --etcd --controlplane --worker
```

On running this script, you are running the `system-agent-install.sh` script hosted on the Rancher URL (which is precisely the [`install.sh` found in the `rancher/system-agent` repo](https://github.com/rancher/system-agent/blob/main/install.sh)) to install the system-agent onto the node with the provided token and CA Checksum for a node that should take on the role of `etcd`, `controlplane`, and `worker`.

Since this takes care of installing the system agent on the provisioned node, the role that we expected Rancher's Bootstrap Provider to take care of has already been accomplished; therefore, there's no need to create any `<Infrastructure>*` CRs in the cluster.

However, we do need to do two things to continue the process:
1. Create a CAPI `Machine` object and something it can reference under `.spec.infrastructureRef` that tells CAPI that it's safe to proceed
2. Create a dummy `RKEBootstrap` that can be referenced by the `Machine` object under `.spec.bootstrap.configRef` so that CAPI doesn't fail out, despite the fact that our bootstrapping is already complete

To do this, the script will automatically also make a request to the Rancher API at `https://<RANCHER_URL>/v3/connect/agent`, which points to the **RKE Config Server** running in Rancher.

On seeing a request from a machine, the **RKE Config Server** will attempt to see if the machine is already registered (in which case it will do nothing); if the machine is not registered, it will create a ephemeral Secret of the type `rke.cattle.io/machine-request` named `custom-<hash-of-machine-name>` in the same namespace; this Secret will effectively just contain the headers on the request that was made to Rancher.

On seeing a Secret of this type get created, the Provisioning V2 controllers will automatically create a couple of objects on behalf of the Secret (which is subsequently deleted after 1 minute):
- The CAPI `Machine`
- A `CustomMachine`, which takes the place of an `<Infrastructure>Machine`. It's the only type of Infrastructure Provider CRD that the Rancher Infrastructure Provider controllers will ignore and not do any processing for.
- A dummy `RKEBootstrap` that is referenced by the CAPI `Machine`

Since the Rancher controllers will always mark a `CustomMachine`'s status as immediately `Ready`, the cluster will finish provisioning immediately after this happens.

From here, you can skip to the stages around bootstrapping to see the next thing that happens to these `CustomMachines` to get the k3s / RKE2 components set up.

### Imported Clusters

An Imported Cluster in Rancher is a Kubernetes cluster that has been externally imported into Rancher. 

In this case, the Kubernetes API is already up so Rancher can simply create the `provisioning.cattle.io` Cluster object with a `nil` value for the `rkeConfig` and no CAPI objects are created. 

No more stages for provisioning or bootstrapping are executed.