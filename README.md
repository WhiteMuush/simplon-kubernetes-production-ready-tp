# <img src="https://cdn.simpleicons.org/kubernetes" height="28" alt="Kubernetes" align="center"/> Production Ready: CPU & memory management on Kubernetes <img src="https://cdn.simpleicons.org/go" height="28" alt="Go" align="center"/>

![Go](https://img.shields.io/badge/Go-1.26-00ADD8?logo=go&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-Kind-326CE5?logo=kubernetes&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-distroless-2496ED?logo=docker&logoColor=white)
![Status](https://img.shields.io/badge/status-work%20in%20progress-orange)

Three Go microservices (API Gateway, Books, Movies) already deployed and replicated on a Kind cluster. This iteration adds resource governance: `requests` and `limits` on every container, then a `LimitRange` and a `ResourceQuota` to keep the namespace under control.

> Brief: [docs/CONSIGNES.md](docs/CONSIGNES.md)

## Why

Right now the pods have no resource boundaries. A memory leak in one service can eat the whole node, and a busy loop can starve every other container sharing the same CPU. The goal here is to make that impossible, and to understand the two knobs that do it:

- **Requests**: what the scheduler reserves for the container. It is a guarantee, and it is what placement decisions are based on.
- **Limits**: the ceiling. Above it, CPU gets throttled (the container slows down) while memory gets the container OOMKilled (it dies).

CPU is compressible, memory is not. That asymmetry is the reason the two behave so differently when the limit is reached, and it drives how the values are picked.

## Architecture

```
              HOST  (http://localhost:8080/data)
                          │
                          ▼  LoadBalancer (cloud-provider-kind)
                          │
              Kind cluster (1 control-plane + 1 worker)
                          │
              ┌───────────┼───────────┐
              │           │           │
             api        books       movies
        (LoadBalancer) (ClusterIP) (ClusterIP)
```

One Docker image, three binaries, the container `command` picks the app. The API reaches the others by Service DNS name, injected as `BOOKS_API_HOST=books` and `MOVIES_API_HOST=movies`.

| App | Endpoint | Exposure |
|---|---|---|
| api | `GET /data` | LoadBalancer, aggregates the two others |
| books | `GET /books` | ClusterIP |
| movies | `GET /movies` | ClusterIP |

## Requirements

Docker, [kind](https://kind.sigs.k8s.io/), kubectl, and cloud-provider-kind for LoadBalancer support:

```bash
go install sigs.k8s.io/cloud-provider-kind@latest
```

## Setup

```bash
docker build -t microservices:1.0 .
make create-cluster          # cluster + image load
make deployments services
sudo cloud-provider-kind     # keep running in its own terminal
```

Kind ships without a metrics-server, and nothing resource related can be observed without it:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.9.0/components.yaml

kubectl patch -n kube-system deployment metrics-server --type=json \
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```

The `--kubelet-insecure-tls` patch is needed because Kind's kubelets serve self-signed certificates that the metrics-server refuses by default.

Check it answers, then call the API:

```bash
kubectl top nodes
kubectl top pods
curl http://localhost:8080/data
```

```json
{"app":"API Gateway","data":{"books":["Book 1","Book 2","Book 3"],"movies":["Movie 1","Movie 2","Movie 3"]}}
```

Cleanup: `make delete-cluster`.

> **WSL2**: cloud-provider-kind may put the LoadBalancer IP on `lo`, and `localhost:8080` then hangs. Fix with `sudo ip addr del <EXTERNAL-IP>/32 dev lo`, re-run if it comes back.

## Progress

| Step | Status |
|---|---|
| Cluster rebuilt with a single worker node | todo |
| metrics-server installed and patched | todo |
| requests & limits on the 3 Deployments | todo |
| Throttling experiment (CPU limit at `1m`) | todo |
| LimitRange (defaults + min/max per namespace) | todo |
| ResourceQuota (namespace ceiling) | todo |
| Tests after the quota, rejected pods observed | todo |

## Notes

Kept as a scratchpad while working through the brief, to be turned into a proper analysis section once the measurements are done.

- `kind-config.yaml` still describes the 9 worker, 3 zone cluster of the previous iteration. It has to be cut down to one worker so the resource pressure is actually visible.
- The Deployments in `k8s/` carry no `resources` block yet.
- Open question: with a `1m` CPU limit, how long does the API Gateway take to answer, and how does that show up in `container_cpu_cfs_throttled_periods_total`.
- Open question: does a LimitRange default apply to pods created before it exists (expected: no, only to new ones).
