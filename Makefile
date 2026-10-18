TF        := terraform -chdir=terraform
CLUSTER   := learn-deployment
KUBECTX   := kind-$(CLUSTER)
K         := kubectl --context $(KUBECTX)

.PHONY: help tools lint up down status password ui open repo

help: ## Show targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

tools: ## Install missing CLIs with Homebrew
	brew install kind terraform argocd kustomize

lint: ## Validate Helm chart, Kustomize overlays and Terraform offline
	helm lint gitops/charts/hello -f gitops/envs/dev/hello.yaml
	helm lint gitops/charts/hello -f gitops/envs/prod/hello.yaml
	helm template hello-dev gitops/charts/hello -f gitops/envs/dev/hello.yaml > /dev/null
	kubectl kustomize gitops/apps/whoami/overlays/dev  > /dev/null
	kubectl kustomize gitops/apps/whoami/overlays/prod > /dev/null
	$(TF) fmt -check -recursive
	$(TF) init -backend=false -input=false > /dev/null && $(TF) validate
	@echo "lint OK"

repo: ## Create a public GitHub repo from this folder and push (Argo CD pulls from it)
	gh repo create learn-deployment --public --source=. --remote=origin --push
	@echo "gitops_repo_url = \"$$(gh repo view --json url -q .url).git\"" > terraform/terraform.tfvars
	@cat terraform/terraform.tfvars

up: ## Create kind cluster + Argo CD + root app
	$(TF) init -input=false
	$(TF) apply -auto-approve
	@$(MAKE) --no-print-directory password

down: ## Destroy everything
	$(TF) destroy -auto-approve

status: ## Show Argo CD applications and app pods
	$(K) -n argocd get applicationsets,applications
	$(K) get ingress -A

password: ## Print Argo CD admin password
	@printf "Argo CD: http://argocd.localtest.me  user=admin  password="
	@$(K) -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo

ui: ## Port-forward Argo CD UI to localhost:8081 (before Traefik is up)
	$(K) -n argocd port-forward svc/argocd-server 8081:80

open: ## Open all the sample URLs
	open http://argocd.localtest.me http://hello-dev.localtest.me http://hello-prod.localtest.me \
	     http://whoami-dev.localtest.me http://whoami-prod.localtest.me
