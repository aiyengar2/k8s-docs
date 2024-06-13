# WIP: Do Not Read
### What types of "Applications" do we deploy in Kubernetes?

Typically, we deploy **Services** onto Kubernetes, which are applications that generally do three things:
1. Perform automated tasks
  - i.e. grab data from one location and publish it at another
2. Respond to local events
  - i.e. watch processes and start them back up if they are unhealthy, like `kubelet`
3. Listen to data requests from other applications and respond to them
  - i.e. listen to requests from applications like `kubectl` and return responses, like the Kubernetes API Server

Services generally are designed to serve "content" at a particular "endpoint" that is accessible by users.

> **Note**: As 

Generally, the protocol that is used to retrieve the "content" at that "endpoint" is HyperText Transfer Protocol (HTTP), which is generally used by most applications to allow "clients" communicate with "servers" (in this case, your backend service).

Often times, this "content" is read by a user-facing application and rendered in more human-readable way; for example, a CLI tool like kubectl will be able to make "calls" to grab content from a service (the Kubernetes API Server) at its published endpoint (i.e. `my-api-server.endpoint:6443`) and render it in a human-readable format on your command line on executing a call like `kubectl get nodes`.

Alternatively, the "content" returned by your service may be HTML, CSS, and Javascript content; in this case, your browser into an interactive application

The "content" generally forms an interface that you can use to communicate with the application, i.e. an Application Programming Interface (API).

Most commonly, the "content" that is served is accessible by making a call using a protocol called HTTP, which is why services most commonly serve up HTTP APIs. However, 

