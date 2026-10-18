# learn-deployment

A local sandbox for practising how **Terraform → Argo CD (GitOps) → Helm / Kustomize** fit together.
Everything runs on your Mac in a `kind` cluster; Git (GitHub) is the source of truth.

```
terraform apply
  ├─ kind cluster                          (infra — would be VPC/EKS in the cloud)
  ├─ Argo CD (helm_release)                (bootstrap the GitOps controller)
  ├─ cluster secret w/ annotations         (the "bridge": TF facts → Argo CD)
  └─ root Application → gitops/argocd-apps (app of apps)
                              │
        ┌─────────────────────┼─────────────────────────┐
   traefik (ApplicationSet)  hello (ApplicationSet)    whoami (ApplicationSet)
   3rd-party Helm chart      our Helm chart × dev/prod  Kustomize, 1 app per overlay dir
   + values in Git           + env values files         (git directory generator)
```

| Layer | Where | Who applies it |
|---|---|---|
| Cluster, Argo CD, bridge secret, root app | `terraform/` | you, `make up` |
| Platform add-ons (ingress) | `gitops/platform/`, `gitops/argocd-apps/traefik.yaml` | Argo CD |
| Our Helm chart + per-env values | `gitops/charts/hello/`, `gitops/envs/*/` | Argo CD |
| Plain YAML + Kustomize overlays | `gitops/apps/whoami/` | Argo CD |

## Prerequisites

Docker Desktop running, plus `kind terraform kubectl helm gh` (`make tools` installs the missing ones via Homebrew).

## Run it

```bash
make lint      # offline checks: helm lint, kustomize build, terraform validate
make repo      # gh: create a public GitHub repo, push, write terraform/terraform.tfvars
make up        # kind + Argo CD + root app (≈3–5 min)
make status    # watch ApplicationSets → Applications appear
make open      # open the URLs below
```

| URL | What |
|---|---|
| http://argocd.localtest.me | Argo CD UI (`make password` for admin login) |
| http://hello-dev.localtest.me / http://hello-prod.localtest.me | podinfo via our Helm chart |
| http://whoami-dev.localtest.me / http://whoami-prod.localtest.me | whoami via Kustomize |

`*.localtest.me` resolves to 127.0.0.1, so no `/etc/hosts` edits. Port 80 on your Mac → kind node → Traefik.
Until Traefik is synced, use `make ui` (port-forward to http://localhost:8081).

> Using a different repo name or a private repo? Edit `terraform/terraform.tfvars` by hand;
> for private repos add a repo credential secret in the `argocd` namespace.

## Exercises (each one = edit → commit → push → watch Argo CD)

1. **Config change** – change `message` in `gitops/envs/dev/hello.yaml`. Only `hello-dev` syncs.
2. **Scale prod** – bump `replicaCount` in `gitops/envs/prod/hello.yaml`.
3. **Self-heal** – `kubectl -n hello-dev scale deploy hello-dev-hello --replicas=5`; Argo CD reverts it.
4. **New environment, zero Argo config** – `cp -r gitops/apps/whoami/overlays/dev gitops/apps/whoami/overlays/staging`, change the host, push. The git directory generator creates `whoami-staging` by itself.
5. **Add env to the Helm app** – add `- env: staging` to `argocd-apps/hello.yaml` and create `envs/staging/hello.yaml`.
6. **Chart change** – add a `ConfigMap` template to `charts/hello`, bump `version` in `Chart.yaml`.
7. **Rollback** – `git revert HEAD && git push`.
8. **Terraform → cluster value** – add an annotation to `kubernetes_secret_v1.in_cluster` in `terraform/main.tf`, `terraform apply`, then use it in an ApplicationSet template (`{{ .metadata.annotations.<key> }}`), like `clusterName` in `argocd-apps/hello.yaml`. This is how IAM role ARNs / bucket names reach Helm values in the cloud.
9. **Add a platform add-on** – e.g. metrics-server: copy `argocd-apps/traefik.yaml`, swap chart/repo, add `platform/metrics-server/values.yaml`.
10. **Pin versions** – replace `targetRevision: "*"` (Traefik) and set `argocd_chart_version` once everything works.

## Tear down

```bash
make down
```

## Moving to a real cloud later

Only `terraform/` really changes: swap `kind_cluster` for a VPC + EKS/GKE module, put state in a remote backend (S3/GCS),
and add cloud outputs (IRSA role ARNs, bucket names) as annotations on the cluster secret. `gitops/` stays almost the same.
See `gitops-bridge-dev/gitops-bridge` and `aws-ia/terraform-aws-eks-blueprints`.
