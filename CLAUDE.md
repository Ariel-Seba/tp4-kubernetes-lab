# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Kubernetes hands-on lab for the DiploDevOps course. Uses K3d (K3s in Docker) to run a local cluster on macOS. The lab deploys nginx, demonstrates scaling, and explores Kubernetes networking (ClusterIP, NodePort, CoreDNS).

## Cluster Setup

The target cluster is `curso-k8s`. K3d stores its kubeconfig separately from the default `~/.kube/config`:

```bash
export KUBECONFIG=/Users/ariel.a.seba/.config/k3d/kubeconfig-curso-k8s.yaml
```

If `kubectl get nodes` returns a connection refused error, check that `KUBECONFIG` points to the right file and that the cluster is running:

```bash
k3d cluster list
k3d cluster start curso-k8s   # if stopped
kubectl config current-context
```

## Working with the manifests

All manifests live in `kubernetes-lab/`. Apply them against the `curso-k8s` cluster:

```bash
kubectl apply -f kubernetes-lab/nginx-deployment.yaml
kubectl apply -f kubernetes-lab/nginx-service.yaml
kubectl apply -f kubernetes-lab/nginx-nodeport.yaml
```

Verify state:

```bash
kubectl get all
kubectl get pods -o wide        # shows which node each pod runs on
kubectl get svc
kubectl get endpoints nginx-service
```

Scale the deployment:

```bash
kubectl scale deployment nginx --replicas=6
```

## Networking validation

Test internal DNS and ClusterIP routing with a temporary pod:

```bash
kubectl run curlpod --rm -it --image=curlimages/curl -- sh
# inside: curl http://nginx-service
```

Test CoreDNS resolution:

```bash
kubectl run test --rm -it --image=busybox -- sh
# inside: nslookup nginx-service
```

## Known limitation

The `curso-k8s` cluster was created **without** mapping NodePort 30080 to the macOS host, so `localhost:30080` does not work from outside the cluster. NodePort is accessible only from within the cluster network. To expose ports to the host, the cluster must be recreated with `--port` flags:

```bash
k3d cluster create curso-k8s --port "30080:30080@loadbalancer"
```

## Manifest structure

| File | Kind | Purpose |
|------|------|---------|
| `nginx-deployment.yaml` | Deployment | 3 replicas of `nginx:latest`, port 80 |
| `nginx-service.yaml` | Service/ClusterIP | Internal cluster access on port 80 |
| `nginx-nodeport.yaml` | Service/NodePort | Exposes port 80 via node port 30080 |

Labels/selectors use `app: nginx` throughout — all three resources are linked by this label.
