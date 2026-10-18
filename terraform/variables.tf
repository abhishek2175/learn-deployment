variable "cluster_name" {
  description = "Name of the local kind cluster."
  type        = string
  default     = "learn-deployment"
}

variable "environment" {
  description = "Label stamped on the Argo CD cluster secret; ApplicationSets read it."
  type        = string
  default     = "local"
}

variable "gitops_repo_url" {
  description = "Git repo Argo CD watches, e.g. https://github.com/<you>/learn-deployment.git"
  type        = string
}

variable "gitops_revision" {
  description = "Branch, tag or commit Argo CD tracks."
  type        = string
  default     = "main"
}

variable "argocd_chart_version" {
  description = "argo-cd Helm chart version. null = latest; pin it once things work."
  type        = string
  default     = null
}

variable "http_port" {
  description = "Host port mapped to the ingress controller (Traefik) on the kind node."
  type        = number
  default     = 80
}
