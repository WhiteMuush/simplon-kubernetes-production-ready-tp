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

##@ Workloads

.PHONY: deployments
deployments: ## Apply the api, books and movies deployments
	@echo "----------------api deployment---------------"
	@kubectl apply -f ./k8s/api/api-deployment.yaml
	@echo "---------------------------------------------"
	@echo "---------------books deployment--------------"
	@kubectl apply -f ./k8s/books/books-deployment.yaml
	@echo "---------------------------------------------"
	@echo "---------------movies deployment-------------"
	@kubectl apply -f ./k8s/movies/movies-deployment.yaml
	@echo "---------------------------------------------"

.PHONY: services
services: ## Apply the api, books and movies services
	@echo "-----------------api service-----------------"
	@kubectl apply -f ./k8s/api/api-service.yaml
	@echo "---------------------------------------------"
	@echo "----------------books service----------------"
	@kubectl apply -f ./k8s/books/books-service.yaml
	@echo "---------------------------------------------"
	@echo "----------------movies service---------------"
	@kubectl apply -f ./k8s/movies/movies-service.yaml
	@echo "---------------------------------------------"
