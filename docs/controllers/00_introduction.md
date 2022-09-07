# Introduction To Controllers

## Prerequisites

It is expected that the reader of this material has a basic familiarity with Kubernetes, such as that of an average Kubernetes user who has interacted with Kubernetes resources in a cluster before via `kubectl` or some via other UI  (e.g. the Rancher UI) that exposes the names of underlying Kubernetes resources like `Pods`, `Deployments`, `Services`, etc.

## Introduction

### What is Kubernetes? (High-Level)

Kubernetes is open-source orchestration software for deploying, managing, and scaling distributed "self-contained, mostly-environment-agnostic processes running in a sandbox" (`Containers`) running on one or more servers (`Nodes`).

In essence, Kubernetes can be thought of as a multi-server equivalent of Docker: whereas executing `docker ps` will list all of the Docker-managed processes (`Containers`) running on your single server, in Kubernetes executing a `kubectl get pods --all-namespaces` will list all of the sets of Kubernetes-managed processes (`Pods`) running on every server (`Node`) that has registered with the Kubernetes API.

For a deeper dive into how processes are managed in Kubernetes, please read the docs on [Process Management In Kubernetes](../process_management/00_introduction.md).

