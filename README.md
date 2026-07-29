# <img src="https://cdn.simpleicons.org/kubernetes" height="28" alt="Kubernetes" align="center"/> HA multi-zone Go microservices on Kubernetes <img src="https://cdn.simpleicons.org/go" height="28" alt="Go" align="center"/>

![Go](https://img.shields.io/badge/Go-1.26-00ADD8?logo=go&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-Kind-326CE5?logo=kubernetes&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-distroless-2496ED?logo=docker&logoColor=white)

Three Go microservices (API Gateway, Books, Movies) deployed in strict High Availability on a Kind cluster of 9 workers spread over 3 simulated zones.

> Brief of the previous iteration (single-zone HA): [docs/CONSIGNES.md](docs/CONSIGNES.md)

## Collaborators

| | Name | GitLab |
|---|---|---|
| <img src="https://gitlab.com/uploads/-/system/user/avatar/25079794/avatar.png?width=48" width="48" height="48" alt="Melvin PETIT avatar"/> | Melvin PETIT | [@WhiteMuush](https://gitlab.com/WhiteMuush) |
| <img src="https://secure.gravatar.com/avatar/517f74b6241ee925a3bfa3bfcf2febedc774773db90295c061b2cba360a173ad?s=48&d=identicon" width="48" height="48" alt="Leith Zniber avatar"/> | Leith Zniber | [@Bambstk](https://gitlab.com/Bambstk) |

## Project context

Deploy the app in HA on a local Kind cluster: 9 workers (3 per zone) across 3 AZ (`francecentral-1`, `-2`, `-3`), zones simulated with node labels.

- 3 replicas per service, mandatorily spread over different zones (Required anti-affinity or strict topologySpreadConstraints), plus an optional constraint favouring "empty" nodes.
- API Gateway reachable from the host.
- StartupProbe, ReadinessProbe, LivenessProbe, so traffic only reaches healthy and ready pods.
- Rolling Update with no interruption, checked with `kubectl rollout` and a continuous load test.
- Chaos: drain a node, then a whole zone. Siege must show a low error rate (< 1-2%).
- Deliverable: live demo of the 3 load tests (normal, node down, zone down) plus an analysis of the failure impact and of the orchestrator's role.

Bonus: Traffic Distribution Policy, PodDisruptionBudget. Neither is implemented yet, and the manifests are raw YAML, not Helm/Kustomize.

## Architecture

```
                         HOST  (http://localhost:8080/data)
                              │
                              ▼  LoadBalancer (cloud-provider-kind)
                              │
                   FRANCE (Kind cluster "francecentral")
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
 zone francecentral-1   zone francecentral-2   zone francecentral-3
        │                     │                     │
  control-plane-1        control-plane-2        control-plane-3    (tainted, no app pods)
        │                     │                     │
   ┌────┼────┐            ┌────┼────┐            ┌────┼────┐
 worker worker worker   worker worker worker   worker worker worker
   │      │      │         │      │      │         │      │      │
  pod    pod    pod       pod    pod    pod       pod    pod    pod
 (api) (books)(movies)   (api) (books)(movies)   (api) (books)(movies)
```

`podAntiAffinity` (required, `topologyKey: zone`) forces exactly one pod per app per zone; `topologySpreadConstraints` (soft, `topologyKey: kubernetes.io/hostname`) then spreads those 9 pods one per worker instead of stacking them. `api` is the only one reachable from outside (LoadBalancer); `books` and `movies` stay ClusterIP, called by `api` over Service DNS.

One Docker image, three binaries, the container `command` picks the app. The API reaches the others by Service DNS name, injected as `BOOKS_API_HOST=books` and `MOVIES_API_HOST=movies` (port 80, so no suffix).

| App | Endpoint | Exposure |
|---|---|---|
| api | `GET /data` | LoadBalancer, aggregates the two others |
| books | `GET /books` | ClusterIP |
| movies | `GET /movies` | ClusterIP |

The API serves `/data`, not `/`.

## HA config

Every Deployment carries the same three blocks:

- **`podAntiAffinity` required on `topologyKey: zone`**: two pods of the same app can never share a zone. With 3 replicas and 3 zones, the only valid placement is one per zone, and a pod that cannot satisfy it stays `Pending` rather than land in the wrong place.
- **`topologySpreadConstraints` on `kubernetes.io/hostname`, `ScheduleAnyway`, selector `app Exists`**: counts all three apps together to avoid stacking them on one worker while others stay empty. Soft preference, so it never blocks scheduling.
- **`maxSurge: 0`, `maxUnavailable: 1`**: with `maxSurge: 1` the extra pod would have no free zone and the rollout would deadlock on `Pending`. Deleting first frees a zone, and 2 of 3 replicas keep serving.

Probes are TCP on 8080: startup (`failureThreshold 30`, `period 5s`) covers boot, readiness pulls the pod out of the Service endpoints when it cannot serve, liveness restarts a stuck container.

## Requirements

Docker, [kind](https://kind.sigs.k8s.io/), kubectl, [siege](https://github.com/JoeDog/siege), and cloud-provider-kind for LoadBalancer support:

```bash
go install sigs.k8s.io/cloud-provider-kind@latest
```

## Deploy

```bash
docker build -t microservices:1.0 .
make create-cluster          # cluster francecentral + image load
make deployments services
sudo cloud-provider-kind     # keep running in its own terminal
```

Check placement (expected: 9 pods, one per app per zone) then call the API:

```bash
make status-cluster
curl http://localhost:8080/data
```

```json
{"app":"API Gateway","data":{"books":["Book 1","Book 2","Book 3"],"movies":["Movie 1","Movie 2","Movie 3"]}}
```

Cleanup: `make delete-cluster`.

> **WSL2**: cloud-provider-kind may put the LoadBalancer IP on `lo`, and `localhost:8080` then hangs. Fix with `sudo ip addr del <EXTERNAL-IP>/32 dev lo`, re-run if it comes back.

## Demo

Watch pods with `watch -n1 kubectl get pods -o wide` and keep traffic running with `siege -c 10 -t 2M http://localhost:8080/data` during each step below.

**Rolling update**

```bash
docker build -t microservices:2.0 . && kind load docker-image microservices:2.0 -n francecentral
kubectl set image deployment/api api=microservices:2.0
kubectl rollout status deployment/api      # kubectl rollout undo to revert
```

**Chaos**

```bash
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data --force   # 1 node, then x3 for a zone
kubectl uncordon <node>
```

Report siege's `Availability`, `Failed transactions` and `Longest transaction` for the three scenarios.

## Analysis

A single node without replication means availability drops to 0 and stays there. Three replicas on one node change nothing: losing the machine loses all three, replication only pays off once it is spread.

Losing one node per zone costs each app one replica per affected zone, but the two other workers of that zone take them back. Rescheduling takes seconds, readiness keeps traffic off the pods still starting, and errors stay in the low single digits, only from the connections in flight at eviction time.

Losing a whole zone removes one third of the capacity for good: the strict anti-affinity forbids rebuilding the replica elsewhere. That is deliberate. A `preferred` rule would restore 3 running replicas at once, but by putting 2 in the same zone, so the next zone failure would take down two thirds instead of one third. `required` trades replica count for guaranteed spreading, which is the right call when the failure domain is what we defend against.

Kubernetes closes the loop without us: probes detect the sick pods, endpoints stop routing to them, evicted workloads are rescheduled under the placement constraints, and the cluster converges back to the desired state as soon as capacity returns. The orchestrator does not prevent failures, it turns "the machine is down" into "the desired state is temporarily unmet".
