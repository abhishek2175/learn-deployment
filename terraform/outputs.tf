output "kubeconfig_path" {
  value = kind_cluster.this.kubeconfig_path
}

output "argocd_url" {
  value = "http://argocd.localtest.me${var.http_port == 80 ? "" : ":${var.http_port}"}"
}

output "argocd_admin_password_cmd" {
  value = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}
