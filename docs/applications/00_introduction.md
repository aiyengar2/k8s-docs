## Prerequisites

It is expected that the reader of this material has a basic familiarity with Kubernetes, such as that of an average Kubernetes user who has interacted with Kubernetes resources in a cluster before via `kubectl` or some via other UI  (e.g. the Rancher UI) that exposes the names of underlying Kubernetes resources like `Pods`, `Deployments`, `Services`, etc. 

A basic familiarity with a programming language (i.e. Golang) is also presumed.

## Introduction to Applications

### What is an Application?

In a generic sense, as defined in Wikipedia, [Application (software)](https://en.wikipedia.org/wiki/Application_software) is "a computer program designed to carry out a specific task other than one relating to the operation of the computer itself, typically to be used by end-users".

### How are simple Applications designed?

Typically, a developer designs a **simple** application by identifying the requirements for that piece of software to execute the desired task and then writing code in a particular language of their choice (Python, Golang, Bash, Java, etc.) that expresses / encodes the logic set out in the requirements.

To write the actual code from the requirements, a developer generally considers the following aspects:

1. **How should the program receive inputs?**
  - i.e. CLI arguments, calls made to / received from an HTTP endpoint, watched "events" (mouse hovers or clicks, system calls, files added and removed from directories), etc.

> **Note:** There may be no inputs as well.
 
2. **How should each of the inputs of the program be translated to actions / outputs the program should make to achieve the requirements?**
  - i.e. if the program receieves an HTTP request, what should it include in the HTTP response?

3. **What are any "external" (not bundled into the program itself) dependencies that this program might have?**
  - i.e. if this is a Bash program, the machine running the program may need to have `curl` installed.
  - i.e. if this program relies on other data files (i.e. `nginx` depending on a static files directory), it is expected that that directory should contain content
  - i.e. if this is a Kubernetes controller, it is expected that this program can load the file in the `KUBECONFIG` environment variable to load the credentials necessary to talk to the Kubernetes API server, can reach out to the Kubernetes cluster defined in that file, and has the permissions in its credentials to operate on the resources it needs to operate on

4. **How do I run the program?**
  - i.e. do I need to compile the code for a specific machine (Golang)?
  - i.e. do I need to run it via an another program / interpreter (Python)?
  - i.e. do I need to both compile the code and run it via another program (Java)?

5. **What should an "operator" / "administrator" be able to configure to alter the behavior of a given program with respect to actions taken on inputs?**
  - i.e. if `DEBUG=1`, make sure you also emit debug logs

> **Note:** Here we identify a different entity than the developer: the operator / administrator (the one who runs the program). This person may not be the same as the user (one who uses the program) but is an essential role to consider with respect to application development in Kubernetes, since the concerns of a developer and the concerns of an operator / administrator are not necessarily the same. More on that later!
>
> **In a DevOps model, the operator / administrator and developer are typically one and the same.**

### How does a Developer run an simple application in a development environment?

Once all of these factors are considered and an application has been written, a developer typically runs a single command (that may itself run one or more commands, i.e. executing a script like `./run.sh`) that starts the program's execution and tests that its functionality works as expected.

>> **Note:** On each execution of a program, a **process** that runs that program is created on that machine; running processes are identifiable by a process ID (i.e. `pid`).

### How does a Developer test running a simple application on other environments?

In order to ensure that the developer builds an application that works in other environments **outside** of the developer's own sandbox, developers leverage **containerization (via `Dockerfiles`)** to produce a **container image**: an artifact that can be deployed by any **container runtime** (Docker, containerd, etc.).

This `Dockerfile` contains instructions on how to reproduce the **minimal environment** required to create this "sandbox" (the image contains this sandbox itself; see [below](#special-topic-how-is-a-dockerfile-defined) for more information) and tells the container runtime what **single command** to run on that environment to get everything up and running.

> **Note:** A "sandbox" is an environment that does not affect the host machine, unless specifically configured to do so (such as with privileged or hostNetwork "sandboxes"). Typically, this sandbox is created on Linux machines using the underlying `cgroups` implementation of the Linux kernel, which allows a Linux user to restrict, record, and isolate the physical resources (CPU, memory, i/o) used by groups of processes. 

> **Note:** The fact that cgroups are used to handle the "sandboxing" of processes directly correlates with the way that Kubernetes handles stuff like resource limits and requests or Quality of Service (QoS) groups for Pods; for more information, read [this article](https://medium.com/geekculture/layer-by-layer-cgroup-in-kubernetes-c4e26bda676c).

On running a `docker build` on this `Dockerfile`, the container image that is produced would then be pushed into a **container registry**, after which the application is ready to be deployed by any container runtime!

#### Special Topic: How is a `Dockerfile` defined?

Just like an onion, the answer is **layer by layer**.

When you look at the internal structure of a Dockerfile, it will look something like this:

```Dockerfile
FROM <mybaseimage>

ENV ... # set necessary env vars at default values
ENV ...
ENV ...

RUN ... # install relevant dependencies
RUN ...
RUN ...

COPY ... # copy in files from the local directory, i.e. ./bin/run.sh
COPY ...

ENTRYPOINT ["./run.sh"] # run this at the very end when running this container
```

Under the hood, when you run a `docker build` using this, it uses `<mybaseimage>` as the underlying **layer** to execute the following commands on and creates a new layer **every time a `RUN` or `COPY` command is executed** (which results in possible changes to the underlying layer's filesystem, such as adding new binaries or copying in data files; the changes that are introduced on top of the previous layer are what define the next layer). 

> **Note:** Since layers comprise of the differences between the **filesystem** of the previous layer and that of the current layer once the `COPY` or `RUN` action has been performed, **a process that is initiated via a `RUN` command will not be re-executed every time the Docker image is run.** It's only the output of having run that command that is stored in the Docker image, not the actual call that is made.

The final layer that is produced is then the one that the single command indicated by `ENTRYPOINT` is executed on running `docker run` on your built image.

### Running complex applications with multiple components in a Kubernetes world

While many applications still run as single, monolithic applications that can be entirely containerized in a single image and deployed in a single container (requiring a single Pod with one container to deploy them) deployed on a single host, some newer applications leverage designs involving multiple containers that form a single logical application. 

For example, Grafana on Kubernetes leverages sidecars that serve as "ConfigMap Reloaders"; processes that watch for ConfigMaps in a cluster and, on seeing contents, copy in the contents to a filesystem accessible by the Grafana process that it is watching for.

> **Note:** For examples of design patterns leveraging these types of "single node multiple container" patterns, see [this article](https://www.weave.works/blog/container-design-patterns-for-kubernetes/)

While these designs can be handled by the design of a single Pod in Kubernetes (i.e. one or more Containers that share a network namespace and have a shared filesystem), running a Pod in Kubernetes instead of a container on a single host often requires users to configure a whole host of other Kubernetes configurations: creating Services and Ingresses to access your endpoints, PVs / PVCs to set up persistent storage, and more arcane resources like PodDisruptionBudgets / PodSecurityPolicies / NetworkPolicies to handle policy enforcement!

This is one of the reasons why developers of these applications often define **Kubernetes manifests** (a set of YAML documents containing multiple resources that will be `kubectl apply`ed to the cluster to deploy the application on a "default" environment) that can be used to more easily deploy these components onto clusters with default configurations.

Aside from just a single application that needs to be deployed, there are more complex applications that are composed of multiple sub-applications (often called **microservices**, or sets of simple applications that communicate with each other statelessly via language-agnostic APIs) as well. A good example of such an application is a Prometheus Monitoring "stack", consisting of exporters that collect metrics, Prometheus which scrapes them and stores the metrics, Alertmanager which passes on alerts receieved from Prometheus, and Grafana which visualizes metrics stored on Prometheus.

For example, to deploy the above applications, the open-source [prometheus-community/kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) project provides **a Helm chart**, a way of packaging applications that we'll talk about next, which ends up deploying around ~206 Kubernetes resources with the default configuration and vastly changes its configuration requirements based on the cluster it is deployed onto!

As the world of applications that need to be deployed onto Kubernetes gets more and more complex / sophisticated, so does the tooling around building and deploying those applications. This will be the topic of the next section.

## Next Up

Next, we will talk about applications in Kubernetes, specifically [Helm](./01_helm.md)!

