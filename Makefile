CLUSTERFILE:=kind-config.yaml
CLUSTERNAME:=francecentral

.DEFAULT_GOAL := help

##@ General

.PHONY: help
help: ## Show this help
	@echo ""
	@echo "Usage: make <target>"
	@awk 'BEGIN { FS = ":.*##" } \
		/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5); next } \
		/^[a-zA-Z0-9_-]+ *:.*##/ { split($$1, t, " "); printf "  \033[36m%-16s\033[0m %s\n", t[1], $$2 }' $(MAKEFILE_LIST)
	@echo ""

##@ Cluster

.PHONY: create-cluster
create-cluster: ## Create the kind cluster and load the microservices image
	@echo "--------------creating cluster---------------"
	@kind create cluster --config $(CLUSTERFILE)
	@echo "---------------------------------------------"
	@echo "----------Loading image in cluster-----------"
	@kind load docker-image microservices:1.0 -n $(CLUSTERNAME)
	@echo "---------------------------------------------"

.PHONY: delete-cluster
delete-cluster: ## Delete the kind cluster
	@kind delete cluster --name $(CLUSTERNAME)
	@echo "---------------------------------------------"

.PHONY: status-cluster
status-cluster: ## Show nodes, pods, services and deployments
	@echo "--------------------NODES--------------------"
	@kubectl get nodes -o custom-columns='NODE:.metadata.name,ZONE:.metadata.labels.zone,STATUS:.status.conditions[-1:].type,INTERNAL-IP:.status.addresses[?(@.type=="InternalIP")].address,EXTERNAL-IP:.status.addresses[?(@.type=="ExternalIP")].address'
	@echo "---------------------------------------------"
	@echo "--------------------PODS---------------------"
	@kubectl get pods -o wide
	@echo "---------------------------------------------"
	@echo "-------------------SERVICE-------------------"
	@kubectl get services
	@echo "---------------------------------------------"
	@echo "------------------DEPLOYMENTS----------------"
	@kubectl get deployments
	@echo "---------------------------------------------"

##@ Load tests (need: cloud-provider-kind --enable-lb-port-mapping)

SIEGE:=siege --concurrent=10 --benchmark http://localhost:8080/data

.PHONY: siege
siege: ## Load test via port-forward (no LoadBalancer needed). Usage: make siege TIME=30S
	@kubectl port-forward svc/api 18080:8080 >/dev/null 2>&1 & PF=$$!; \
	sleep 3; \
	siege --concurrent=10 --benchmark --time=$(or $(TIME),30S) http://localhost:18080/data; \
	kill $$PF 2>/dev/null

.PHONY: test1
test1: ## Load test alone, 100% availability expected
	$(SIEGE) --time=10S

.PHONY: test2
test2: ## Load test, one node drained after 30s
	@( sleep 30; $(MAKE) drain-node ) & $(SIEGE) --time=10S

.PHONY: test3
test3: ## Load test, a whole zone drained after 30s
	@( sleep 30; $(MAKE) drain-zone ) & $(SIEGE) --time=10S

##@ Chaos (called by test2 and test3, or run on their own)

.PHONY: drain-node
drain-node: ## Drain one worker
	@kubectl drain francecentral-worker3 --ignore-daemonsets --delete-emptydir-data

.PHONY: drain-zone
drain-zone: ## Drain every worker of zone francecentral-2
	@kubectl drain francecentral-worker4 francecentral-worker5 francecentral-worker6 --ignore-daemonsets --delete-emptydir-data

.PHONY: restore
restore: ## Put every node back in service and rebalance the pods
	@kubectl uncordon -l zone
	@kubectl rollout restart deployment/api deployment/books deployment/movies

##@ Workloads (Helm)

CHART:=./chart
RELEASE:=microservices

.PHONY: lint
lint: ## Lint the chart and render it without touching the cluster
	@helm lint $(CHART)
	@helm template $(RELEASE) $(CHART) > /dev/null && echo "template OK"

.PHONY: install
install: ## Install or upgrade the release with the default values
	@helm upgrade --install $(RELEASE) $(CHART) --reset-values --rollback-on-failure --timeout 3m

.PHONY: throttle
throttle: ## Re-deploy with the API Gateway capped at 1m CPU
	@helm upgrade --install $(RELEASE) $(CHART) --reset-values -f $(CHART)/values-throttle.yaml --rollback-on-failure --timeout 3m

.PHONY: normal
normal: ## Undo the throttle, back to default values (install does the same)
	@helm upgrade --install $(RELEASE) $(CHART) --reset-values --rollback-on-failure --timeout 3m

.PHONY: uninstall
uninstall: ## Remove the release
	@helm uninstall $(RELEASE)

.PHONY: diff
diff: ## Show what an upgrade would change (needs the helm-diff plugin)
	@helm diff upgrade $(RELEASE) $(CHART)

##@ Resources

.PHONY: metrics-server
metrics-server: ## Install the metrics-server and patch it for kind
	@kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.9.0/components.yaml
	@kubectl patch -n kube-system deployment metrics-server --type=json \
		-p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
	@kubectl rollout status -n kube-system deployment/metrics-server

.PHONY: top
top: ## Show live CPU and memory usage
	@echo "--------------------NODES--------------------"
	@kubectl top nodes
	@echo "--------------------PODS---------------------"
	@kubectl top pods

.PHONY: quota
quota: ## Show what the LimitRange and the ResourceQuota enforce
	@echo "-----------------LIMITRANGE------------------"
	@kubectl describe limitrange microservices-limits
	@echo "----------------RESOURCEQUOTA----------------"
	@kubectl describe resourcequota microservices-quota

WORKER:=francecentral-worker

.PHONY: throttle-proof
throttle-proof: ## Read the CFS throttling counters of the 1m-capped API on the node
	@podman exec $(WORKER) bash -c 'for m in $$(find /sys/fs/cgroup/kubelet.slice -name cpu.max 2>/dev/null); do \
		[ "$$(cat $$m)" = "1000 100000" ] || continue; d=$$(dirname $$m); \
		case "$$d" in *cri-containerd*scope) \
			id=$$(basename $$d | sed "s/cri-containerd-//;s/.scope//" | cut -c1-12); \
			np=$$(grep nr_periods $$d/cpu.stat | awk "{print \$$2}"); \
			nt=$$(grep nr_throttled $$d/cpu.stat | awk "{print \$$2}"); \
			pct=0; [ "$${np:-0}" -gt 0 ] && pct=$$((nt*100/np)); \
			echo "$$id : $$nt/$$np periods throttled ($${pct}%)";; \
		esac; done'
