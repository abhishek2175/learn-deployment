# --- 1. Infrastructure: the cluster -----------------------------------------
# On a real cloud this would be a VPC + EKS/GKE module. kind keeps it local.
resource "kind_cluster" "this" {
  name           = var.cluster_name
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"

      # Traefik (installed later by Argo CD) schedules on this label and binds hostPorts.
      kubeadm_config_patches = [<<-YAML
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
      YAML
      ]

      extra_port_mappings {
        container_port = 80
        host_port      = var.http_port
      }
    }
  }
}

# --- 2. Bootstrap the GitOps controller -------------------------------------
# This is the last thing Terraform installs *inside* the cluster.
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = "argocd"
  create_namespace = true
  wait             = true

  values = [yamlencode({
    configs = {
      params = { "server.insecure" = true } # TLS terminates at Traefik (or not at all locally)
    }
    server = {
      ingress = {
        enabled          = true
        ingressClassName = "traefik"
        hostname         = "argocd.localtest.me"
      }
    }
    dex = { enabled = false }
  })]
}

# --- 3. The bridge: hand Terraform facts to Argo CD -------------------------
# Registers the in-cluster destination with labels/annotations. ApplicationSets
# with a `clusters` generator read these, so values Terraform knows (env, names,
# and in the cloud: IAM role ARNs, bucket names...) flow into Helm values.
resource "kubernetes_secret_v1" "in_cluster" {
  metadata {
    name      = "in-cluster"
    namespace = helm_release.argocd.namespace
    labels = {
      "argocd.argoproj.io/secret-type" = "cluster"
      "environment"                    = var.environment
    }
    annotations = {
      cluster_name  = var.cluster_name
      environment   = var.environment
      repo_url      = var.gitops_repo_url
      repo_revision = var.gitops_revision
    }
  }

  data = {
    name   = "in-cluster"
    server = "https://kubernetes.default.svc"
    config = jsonencode({ tlsClientConfig = { insecure = false } })
  }
}

# --- 4. Root "app of apps" --------------------------------------------------
# Uses the argocd-apps chart so Terraform never needs Argo CD's CRDs at plan time.
resource "helm_release" "root_app" {
  name       = "root-app"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  namespace  = helm_release.argocd.namespace

  values = [yamlencode({
    applications = {
      root = {
        namespace = "argocd"
        project   = "default"
        source = {
          repoURL        = var.gitops_repo_url
          targetRevision = var.gitops_revision
          path           = "gitops/argocd-apps"
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = "argocd"
        }
        syncPolicy = {
          automated = { prune = true, selfHeal = true }
        }
      }
    }
  })]

  depends_on = [kubernetes_secret_v1.in_cluster]
}
