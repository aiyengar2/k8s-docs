## Introduction to Application Development in Kubernetes

### What are Kubernetes Manifests?

As an open source container orchestration platform that focuses on deploying containerized applications, an "application" in Kubernetes is defined as a set of one or more containerized workloads that are being deployed and configured in conjunction in order to execute a specific task, such as offering up a service that is intended to be stood up on top of your Kubernetes infrastructure.

Generally, these resources are deployed via defining a **Kubernetes manifest**, which is a file that contains one or more YAML documents each representing a Kubernetes resource that needs to be installed onto the cluster, and running a command like `kubectl apply -f example.yaml` on the file (assuming the manifest is contained in [`example.yaml`](../../examples/simple-kustomize/example.yaml)).

For example, the following YAML within a file would represent a Kubernetes manifest that simply deploys two ConfigMaps:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-config-map
  namespace: default
data:
  config: |- 
    hello: world
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: my-config-map-2
  namespace: default
data:
  config: |- 
    hello: world
```

On running `kubectl apply -f example.yaml`, these resources would be created or modified to match the contents of this file (if created or modified out-of-band). 

On running `kubectl delete -f example.yaml`, these resources would be deleted.

### Maintaining "Raw" Manifests

While setting up a repository of "raw" manifests that are applied onto a cluster is perfectly sufficient and easily maintainable for deploying your resources onto a **single, pre-defined cluster**, using raw manifests quickly becomes a tricky problem when dealing with multiple clusters that may have slightly tweaked configurations.

Consider a situation in which you would like to deploy the same Kubernetes resources onto different but fairly **homogeneous** clusters (where there aren't too many modifications necessary) but you'd like to make a small modification; for example, let's say you'd only like to deploy one replica of a workload in your `dev` cluster but three replicas of your workload in your `prod` cluster (for high availability). Or, for example, let's say you need to deploy additional resources in `dev` that are not required in `prod` (i.e. a debugging tool).

In this case, you could leverage a different strategy for storing your raw Kubernetes manifests: for example, maintain one set of manifests per cluster, each in different branches of your repository. 

However, the maintanence burden for this may quickly escalate; when you push changes, you'll need to make sure you push it to all of the branches and resolve any conflicts and essentially maintain multiple copies of the exact same code base, despite the fact that only a small amount of configuration logic changes between clusters.

This is where Kustomize comes into play.

### What is Kustomize?

Kustomize is a tool (built into `kubectl`!) that allows you to apply a manifest with additional layers / patches made to the manifest right before it is applied. It is simply defined by adding a `kustomization.yaml` file alongside your manifests that instructs `kustomize` on how to make modifications to your manifest files.

For example, if you view [`examples/simple-kustomize/example.yaml`](../../examples/simple-kustomize/example.yaml) and compare it against the output of running `kustomize build examples/simple-kustomize` at the root of this repository, you will see that the `commonLabels` defined in the [`kustomization.yaml`](../../examples/simple-kustomize/kustomization.yaml) have applied `metadata.labels.app=myapp` to all resources in the outputted Kubernetes manifest.

If you were to directly run `kubectl apply -k examples/simple-kustomize`, you would see the same be persisted onto your Kubernetes cluster's ConfigMaps.

### Why can't we use Kustomize for everything?

While an argument can be made that Kustomize perfectly solves the issues that **most** organizations will have with respect to deploying **their own applications** onto Kubernetes clusters with a vast amount of simplicity, it's important to note the following pitfalls of using Kustomize:

1. Kustomize only handles patching manifests and applying them, like a two-step `kubectl apply`. As a result, it does not offer any features outside of that which a kubectl apply can natively do.
  - i.e. it is declarative, so it does not keep track of whether the resources have already been installed or how many times they have been updated (i.e. storing "release" information)
  - i.e. it is declarative, so you cannot apply conditional, sequential logic on installing / upgrading / removing resources (e.g. pre-install, post-install, pre-upgrade, post-upgrade, pre-delete, post-delete "hooks")
  - i.e. you cannot conditionally leave behind resources on an uninstall
  - i.e. you cannot "rollback" easily to a prior version of an application
  - i.e. you cannot easily define and maintain complicated patching logic
  - i.e. you cannot query live clusters to apply conditional logic based on information like existing resources or Kubernetes version
2. Kustomize requires you to manually maintain every single file you'd like to apply as well as every single patch you'd like to apply on them in the `kustomization.yaml`, which can be painful for complex applications with large numbers of resources
3. Kustomize has no concept of "sharing" applications that have been designed with others
  - While you can share manifests, every organization would need to individually analyze the contents of the manifests being passed on and define their own kustomize file to patch the necessary components to get the application working in their own infrastructure. 
  - While this is a one-time cost, it can be more complicated when multiple organizations need to use the same manifests they are kustomizing and need to re-evaluate their kustomizations on absorbing changes (i.e. having to add new patches when the new base manifests have a new workload resource); each organization essentially needs to have someone who is familiar with the manifest in order to maintain it and upgrade it for changes
  - Kustomize also does not have the concept of a "repository" that can be used to share Kubernetes applications with others

Simply put, while it would still be a recommended choice for simpler applications, it's the simplicity of `kustomize` itself that makes it harder to use on more complex / larger / widely-shared applications that need a higher degree of functionality to be managed and deployed on Kubernetes infrastructure.

This is where Helm comes into play.

### What is Helm?

> **Note**: In these docs, we are only discussing Helm 3. Helm 2 has a slightly different design and is no longer generally used by the Kubernetes community.

[Helm]((https://helm.sh)) is far more **complex**, robust solution around Kubernetes application design and deployment that allows users to both create and publish configurable Kubernetes manifests (i.e. Kubernetes applications).

Unlike Kustomize, which deals only with raw YAML files (both in the form of manifests and the `kustomize.yaml`), Helm deals with the concept of **charts**.

### What is a Helm Chart?

A Helm chart is a "bundle" of files identified by the existence of three paths:

- A `Chart.yaml` file: A file that contains metadata identifying what application is being deployed as well (name, annotations, valid kubeVersion constraint string, etc.) as all subcharts that need to be deployed along with it

- A `templates/` directory: A set of [Go templates](https://golangdocs.com/templates-in-golang) that are expected to produce valid Kubernetes manifests on applying a special `RenderValues` struct, described as the [Built-in Objects](https://helm.sh/docs/chart_template_guide/builtin_objects/) in Helm's documentation.

> **Note**: Another file that is commonly defined is the `templates/NOTES.txt`, which is the only non-YAML file that is evaluated as a Go template in this directory. This file is rendered on a successful install or upgrade to provide additional guidelines to users on how to use their newly installed or upgraded chart.

- A `values.yaml` file (optional): A YAML file that is directly passed into the `RenderValues` struct; **this is predominantly the file users are expected to change to modify applications for their own deployments**. This is Helm's equivalent of a `kustomize.yaml`, except the data model for this file is completely up to a chart owner.

> **Note:** In later releases of Helm, it's expected that chart owners define `values.schema.json` that contains a [JSON Schema](https://json-schema.org) that can be used by Helm to validate the data provided by in a `values.yaml`, but most charts (as of when this doc was written) do not contain a JSON schema.

To see an example of a simple Helm chart, check out the [examples/charts/simple-chart](../../examples/charts/simple-chart).

### How do I define a simple Helm chart?

As long as you define a valid `Chart.yaml` and put valid Kubernetes manifests in the `templates/` directory, **even if they are not Go templates**, Helm will still render the contents.

To ask Helm to render the contents and show you what would be applied on a `helm install`, simply run `helm template <release-name> <path>`. 

For example, run `helm template no-template-chart examples/charts/no-template-chart`, you will see that the contents that are outputted will be the exact same YAML document as the [`examples/charts/no-template-chart/templates/example.yaml`](../../examples/charts/no-template-chart/templates/example.yaml), except that each of the YAML documents representing Kubernetes resources will be prefixed with a comment that identifies the `Source` Go template that rendered it (in this case, `no-template-chart/templates/example.yaml`).

### How do I apply changes to the manifest generated, like `kustomize`?

Unlike `kustomize`, since Helm uses Go templates (and uses [Sprig](https://github.com/Masterminds/sprig) under the hood as well as additional defined functions all documented [here](https://helm.sh/docs/chart_template_guide/function_list)), defining changes to manifests involves using `{{` and `}}` to delimit **"actions"** such as:
- Data evaluations, such as `.Values.commonLabels`
- Control structures, such as `if <condition>`
- More complex expressions involving functions, like `if gt (len (lookup "rbac.authorization.k8s.io/v1" "ClusterRole" "" "")) 0`

For example, if you look at [examples/charts/simple-chart](../../examples/charts/simple-chart), you'll see that the [`configmap.yaml`](../../examples/charts/simple-chart/templates/configmap.yaml) executes the following to populate the `commonLabels` the exact same way that the `kustomization.yaml` encodes it: `{{ .Values.commonLabels | toYaml | nindent 4 }}`.

> **Note:** The `|` syntax used here is documented [here](https://helm.sh/docs/chart_template_guide/functions_and_pipelines/#pipelines), which will automatically take the value executed on the left and pass it in as the last argument to the function on the right. So for example, this would be identical to calling `{{ (nindent 4 (toYaml .Values.commonLabels)) }}`, but the above syntax is much easier to read.
>
> Most commonly, this gets used with the `default <default-value> <value-to-check-if-nil>` function for something like `{{ .Values.myPossiblyNonexistentValue | default "hello world" }}`

But here's a key point with Helm that makes it much more complex than `kustomize`: instead of just having to worry about what YAML to supply, we also had to encode information on **how** to indent the contents at the right location.

If we were to alter the contents of line 4 in the [`configmap.yaml`](../../examples/charts/simple-chart/templates/configmap.yaml) to say `{{ .Values.commonLabels | toYaml | nindent 2 }}` instead (which would place `app: my-app` at the same indentation as `labels:`) and try to run `helm template simple-chart ./examples/charts/simple-chart`, it would still render out the incorrect YAML. 

However, if we were to switch to simulating what would happen on an install via `helm install --dry-run simple-chart ./examples/charts/simple-chart`, we would first get something similar to the following error:

```log
Error: INSTALLATION FAILED: Kubernetes cluster unreachable: Get "https://127.0.0.1:6443/version": dial tcp 127.0.0.1:6443: connect: connection refused
```

This is because a `helm install -dry-run` operation tries to reach out to a non-existent Kubernetes cluster to get certain pieces of information on rendering a template that are **not** applied on a regular `helm template`.

> **Note:** The fact that the behavior of a `helm install -dry-run` does not match a `helm template` is a nuanced but very important point around testing charts before release: since Helm 3 can modify a template based on the contents of a live cluster it is applied on (via modifying the contents passed to the `.Capabilities` Built-In Object around the Kubernetes version or APIs available in the live cluster or modifying the output of a `lookup` call), there are some things that cannot be tested directly via Helm without either passing in additional command line arguments (such as `--kube-version`) or in the worst case (i.e. `lookups`) spinning up a live cluster. 
>
> `lookups` are a specific example that cannot even be caught by a `helm install --dry-run`; it is this fact that `lookups` automatically always return no objects that allows the example code in [`prevent-install.yaml`](../../examples/charts/simple-chart/templates/prevent-install.yaml) to never be run on a `helm install --dry-run` or a `helm template` (since there will never be a `ClusterRole` returned in either `lookup` call) but to never fail on a live cluster (since all real clusters always have at least one `ClusterRole` returned there.)
>
> In fact, try running a `helm install` omitting the `--dry-run`. You'll get the following error:
>
> ```log
> Error: INSTALLATION FAILED: execution error at (simple-chart/templates/prevent-install.yaml:2:6): This chart is not ever intended to be installed onto a live cluster. This failure will only ever be emitted on an attempt to install this chart.
> ```

Even if you were to fix your local setup to point to a valid Kubernetes cluster, you would see the following error instead:

```log
Error: INSTALLATION FAILED: unable to build kubernetes objects from release manifest: error validating "": error validating data: ValidationError(ConfigMap.metadata): unknown field "app" in io.k8s.apimachinery.pkg.apis.meta.v1.ObjectMeta
```

Which makes sense, since `.metadata.app` is invalid. Only `.metadata.labels.app` is valid.

### Reading Go template "actions"

While the previous examples given above are fairly simple to read, more complex invocations of Go template "actions" may look fairly unreadable, such as:

`if gt (len (lookup "rbac.authorization.k8s.io/v1" "ClusterRole" "" "")) 0`

However, the trick to reading these templates is to go from in-to-out, similar to [Lisp](https://en.wikipedia.org/wiki/Lisp_(programming_language)) and other dialects of it like [Scheme](https://en.wikipedia.org/wiki/Scheme_(programming_language)) or [Clojure](https://en.wikipedia.org/wiki/Clojure).

For example, when evaluating the above first start at the center, which reads as "lookup if there are any ClusterRoles defined in the cluster): `lookup "rbac.authorization.k8s.io/v1" "ClusterRole" "" ""`

Then peel the onion out: `len (<all-clusterroles-in-cluster>)`

Again: `gt <num-clusterroles-in-cluster> 0`

And again: `if <num-clusterroles-in-cluster-is-greater-than-0>`

Therefore, this complex conditional essentially reads as "If the number of `ClusterRoles` in this cluster is greater than 0, execute what is within this block".

### Dashes in Action Blocks

If you look at the Go templates defined in the [simple-chart](../../examples/charts/simple-chart), you might have noticed that some blocks have dashes on the left (`{{- if <condition>}}`), some have dashes on both sides (`{{- define "<named-template>" -}}`), and some have no dashes (`{{ .Values.commonLabels | toYaml | nindent 4 }}`). In other charts, there could even be dashes just on the right!

The reason why dashes are included in Go templates is to indicate whether or not the previous or next newline should be removed.

For example, if you were to modify the chart to move `{{ .Values.commonLabels | toYaml | nindent 4 }}` down to line 4 (without a preceding indentation) and run `helm template simple-chart ./examples/charts/simple-chart`, you would see that the ConfigMap you modified has an unnecessary newline between `labels:` and `app: my-app`, which makes sense since you added it. However, without changing the extra new-line you added, if you modified the call to `{{- .Values.commonLabels | toYaml | nindent 4 }}`, you would see that the preceding newline got removed!

The reason why this does not matter with respect to `define` blocks is because the `_helpers.tpl` file (or any file starting with `_`) isn't actually rendered, so it doesn't matter if we remove the preceding newline. However, for `if` blocks, if we did not remove the preceding newline (i.e. the newline that the `if` block resides in), every `if` block would leave behind unnecessary newlines.

Therefore, by convention, it's a good idea to:
- Start named templates with dashes on both sides
- Start conditional blocks with `-`
- Use `nindent` (which creates a newline before automatically) instead of `indent`, with no dashes

For more information, see [the Helm docs](https://helm.sh/docs/chart_template_guide/control_structures/#controlling-whitespace).

### Passing in additional values to a Helm chart

To modify the default `values.yaml` passed to a chart, you have multiple command line options (`--set`, `--set-file`, `--set-string`, `-f`) that can be used in conjunction to pass in modifications. This is described in the [Helm docs](https://helm.sh/docs/chart_template_guide/values_files/) in more detail.

These modifications can be used by the chart to apply completely new configurations, including overlaying entire files.

For example, if you run `helm template simple-chart --set secret.enabled=true ./examples/charts/simple-chart`, you'll see the the conditional on [`secret.yaml`](../../examples/charts/simple-chart/templates/secret.yaml) successfully executes, which results in the template successfully now producing two additional `Secret` objects as described!

### Embedding local files

By utilizing the `.Files` object in the `RenderValues` struct, you can also embed file contents (from files idiomatically placed in the `files/` directory) into your manifest! 

For example, you may have noticed that both the [`configmap.yaml`](../../examples/charts/simple-chart/templates/configmap.yaml) and [`secret.yaml`](../../examples/charts/simple-chart/templates/secret.yaml) embed files in `files/` using the following Go template "actions":

```go
{{ (.Files.Glob "files/ingress-nginx/*").AsConfig | indent 2 }}
```

```go
{{ (.Files.Glob "files/secret/*").AsSecrets | indent 2 }}
```

If you were to modify the contents of these files (or add new files), they would also automatically show up in the newly generated templates.

For more information on how to work with `.Files`, see [the Helm docs](https://helm.sh/docs/chart_template_guide/accessing_files/).

### Using Named Templates or Variables

When dealing with a fairly complex piece of logic for some Helm code that is going to be reused in several locations (i.e. calculating common labels based on multiple values.yaml fields), it's a good idea to use a Named Template that should be located in a `_helpers.tpl` file and include it in your template via `{{ include "<named-template-name>" <scope> }}` (where `<scope>` is typically `.`, but can be something like `.Values`).

For an example of how this is used, see the logic in [`specialconfigmap.yaml`](../../examples/charts/simple-chart/templates/specialconfigmap.yaml) which uses the template defined in the [`_helper.tpl`](../../examples/charts/simple-chart/templates/_helper.tpl) that expects the scope passed in to be `.`; you can also see what happens when a non-default scope like `.Values` is passed in by viewing [`specialconfigmap2.yaml`](../../examples/charts/simple-chart/templates/specialconfigmap2.yaml).

As described in [the Helm docs](https://helm.sh/docs/chart_template_guide/named_templates/), you could also use `template`, however:

> It is considered preferable to use include over template in Helm templates simply so that the output formatting can be handled better for YAML documents.

While this won't be discussed in detail in this document, you can also use [variables](https://helm.sh/docs/chart_template_guide/variables/) declared similar to the way they are declared in Golang to store intermediate values that need to be accessed within blocks that do not have the normal global scope (e.g. [`with` blocks](https://helm.sh/docs/chart_template_guide/control_structures/#modifying-scope-using-with)).

### Using Information from the Live Cluster For a Template

While this won't be discussed in detail in this document, there are generally two sources where you can get information about a live cluster that you are rendering a template for to specifically render certain templates:
1. The `lookup` call: an example is provided in [`prevent-install.yaml`](../../examples/charts/simple-chart/templates/prevent-install.yaml). This provides information about other Kubernetes resources running in the cluster and is equivalent to the output of running a list call with filters using a Kubernetes client that is pointing to the API Server directed to by your current `KUBECONFIG` setting that Helm 3 is leveraging to make the call. This always returns empty on anything except a true `helm install` (including a `helm install --dry-run`), **regardless of what command line arguments are provided**.
2. The `.Capabilities` Built In Object: this provides the Kubernetes version under `.Capabilities.KubeVersion` and provides the equivalent of `kubectl api-resources` on checking `.Capabilities.APIVerisons`. It returns a set of default APIVersions on a `helm template` or `helm install --dry-run` and a fixed KubeVersion unless provided via command-line arguments to either call.

### Working With Subcharts

https://helm.sh/docs/chart_template_guide/subcharts_and_globals/

### Working with Custom Resource Definitions

https://helm.sh/docs/chart_best_practices/custom_resource_definitions/

### How to publish Helm Chart Repositories

https://helm.sh/docs/topics/chart_repository/

## Working with Helm Chart at Rancher

### The `questions.yaml` file (Rancher-only)

### Rancher Apps & Marketplace