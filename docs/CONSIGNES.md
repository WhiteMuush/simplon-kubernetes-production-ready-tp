# Brief

## Project context

### Summary

You have deployed the microservices application (API Gateway, Books, Movies) on Kubernetes: and it works! You also thought about replicating it 3 times and spreading the pods across several nodes. But for now, our pods do whatever they want. If one of the applications has a problem and its memory grows, no mechanism prevents it from consuming all the memory available on the node (on your PC here). Same for the CPU: we will see that it is a very particular resource, shared between the applications and containers of a same node, so clear constraints must be defined about its usage to avoid a pod cannibalizing our whole infra, and our performance.

We are now going to get a bit closer to a "Production Ready" application, by focusing on CPU & RAM resource management. The goal is to understand the difference between Requests (guaranteed allocation) and Limits (cut-off threshold), and to apply these concepts to the 3 Go services of our application.

You will also have to implement cluster administration mechanisms by setting up a LimitRange to define default and per-namespace constraints, and a ResourceQuota to limit the global consumption of a namespace.

### Note for KIND

On Kind, the metrics-server is disabled by default. To install it, follow this guide: https://gist.github.com/sanketsudake/a089e691286bf2189bfedf295222bd43. Careful, replace version v0.5.0 with a more recent one, such as v0.9.0.

Or run these commands one after the other:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.9.0/components.yaml

kubectl patch -n kube-system deployment metrics-server --type=json \
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```

### Typical schedule

1. **Theory & Concepts (1h)** -> After the morning class, we sit down and read the Kubernetes documentation about resources
2. **Environment setup (30mn)** -> We (re)create a Kind cluster from scratch, with a single worker node
3. **Install the "metrics-server" (15mn)** -> Kind does not install it, and it is required to display & manage resources on a Kubernetes cluster
4. **Resources configuration (1h30)** -> We take our 3 Deployments, and apply resource limits & requests on them
5. **Test & observe (30mn)** -> Set very low CPU limits (1m?) and observe the "throttling" effect and the high latency
6. **Cluster administration: LimitRange & ResourceQuota (1h)** -> Apply your austerity policy on resources, set up rationing!
7. **Test again & observe (30mn)** -> Create new pods, observe their (non) creation, check that what you set up still works (or not)
