# Chapter 10. Deploying Real-World Projects with GitOps on Kubernetes

Companion code for *Implementing GitOps with Kubernetes, 2nd Edition*.

The chapter explains the design and the trade-offs. **This README holds the
complete keystroke-level walkthrough** (AKS, with the EKS delta), so that it
can be followed at a terminal and corrected as the tools move. Before a first
run against real clusters, read [`TESTING.md`](TESTING.md).

---

## What changed since the first edition

The first edition (`first_edition/real-world-projects`, kept unchanged for
reference) built one AKS cluster with Terraform from a GitHub workflow, pushed
an image to Docker Hub, applied manifests with `kubectl` from the same
workflow, and finally installed Argo CD from the pipeline.

| | First edition | Second edition |
|---|---|---|
| Delivery model | Pipeline runs `kubectl apply`, later installs Argo CD | CI builds, signs and pushes only; Kargo changes Git; Argo CD deploys |
| Topology | One AKS cluster | Management cluster (Argo CD hub + Kargo), non-production and production clusters; EKS delta |
| Cloud credentials | Service principal secret in GitHub | GitHub OIDC and Entra Workload ID everywhere; no stored secret |
| Registry | Docker Hub, tag edited by hand | ACR, semantic version per build, signed with cosign |
| Exposure | `Service` of type `LoadBalancer`, HTTP | Gateway API (Envoy Gateway) with TLS from cert-manager; Ingress-NGINX is retired |
| Argo CD | Installed by the pipeline, public IP, admin password in the job log | Self-managed 3.5.6 hub, reconciles itself, no public endpoint |
| Application secret | `kubectl create secret` in the pipeline | External Secrets Operator + Key Vault, per-environment identity |
| Environments | One | dev, staging, prod; promotion with Kargo; prod via pull request |
| Releases | Rolling update | Argo Rollouts canary with Prometheus analysis |
| Scaling | HPA `autoscaling/v1`, 5 % CPU target | HPA `autoscaling/v2` with behaviour; KEDA on request rate; VPA recommendations; cluster autoscaler; PDB |
| Load test | Ad-hoc `curl` loop | k6 Job with pass/fail thresholds |
| Monitoring | kube-prometheus-stack + Grafana walkthrough | Metrics contract only (`/metrics`, PodMonitor); dashboards and alerts in Chapter 11 |
| Security | RBAC example (with a broken RoleBinding) | Pod Security `restricted`, default-deny NetworkPolicy, read-only RBAC for Entra groups, quotas; depth in Chapter 12 |
| Application | Python 3.9 Flask, root, port 80 | Node.js 24, non-root, read-only root FS, Redis cache, RED metrics |

---

## Layout

```
chapter10/
├── src/                     weather-app v3 (Node.js 24, Redis cache, /metrics) + tests
├── iac/azure/               three AKS clusters, ACR, Key Vault, federated identities
├── platform/                owned by the platform team
│   ├── hub/                 Argo CD 3.5.6 hub: install, clusters, projects, ApplicationSets
│   ├── addons/              one file per add-on (chart + version) and its values
│   ├── config/workload/     GatewayClass shared by every team
│   └── tenant/              Helm chart: namespace guardrails per environment
├── apps/weather/            owned by the weather team
│   ├── base/                Rollout, Services, cache, PDB, NetworkPolicies
│   ├── components/          opt-in capabilities: metrics, external-secret,
│   │                        public-endpoint, canary-analysis, hpa, keda, vpa
│   └── envs/{dev,staging,prod}/   env.yaml (where) + kustomization.yaml (what)
├── promotion/kargo/         Warehouse, Stages, PromotionTasks, Git credentials
├── ops/load-test/           k6 Job
├── local/                   kind cluster, inner loop and GitOps loop on a laptop
├── ci/.github/workflows/    CI for the app, manifest validation (copy to repo root)
├── scripts/                 render-placeholders.sh, register-cluster.sh
└── first_edition/           first-edition code, unchanged
    ├── real-world-projects/ was old_chapter11_is_now_chapter10/
    └── terraform-flux-cd/   was chapter10/ (first-edition Chapter 10, now Chapter 9)
```

---

## Prerequisites

* An Azure subscription where you can create role assignments, and rights to
  read an Entra ID group's object ID.
* A **fork** of this repository. Kargo writes to Git, so it cannot run
  against the upstream repository.
* A DNS zone you control, for `weather-dev`, `weather-staging` and
  `weather-prod.<your-domain>` (step 2.4 creates the records).
* A free API key from <https://www.weatherapi.com/> (optional: while the Key
  Vault secrets hold their placeholder value `REPLACE_ME`, the app serves mock data).
* CLIs: `az` 2.65+, `tofu` 1.9+ (or `terraform`), `kubectl` 1.35+, `kubelogin`,
  `argocd` 3.x, `kargo` 1.12, `kubectl-argo-rollouts` 1.10, `jq`, `docker`,
  `kind` 0.30+.

> **Cost warning.** Three AKS clusters (one on the Standard tier), three
> public load balancers and a Key Vault. Do the cleanup at the end on the
> same day.

---

## Walkthrough

### 0. Local development environment (optional, free)

```bash
cd chapter10/local
./bootstrap.sh              # kind cluster, Argo Rollouts, Argo CD
./bootstrap.sh inner-loop   # build, load, apply: seconds per change
kubectl --context kind-weather-local -n weather-local port-forward svc/weather-app 8081:80
curl -s "http://localhost:8081/api/weather?city=Zurich" -D - | grep -i x-cache
./bootstrap.sh gitops       # local Argo CD follows your current branch
```

### 1. Infrastructure

```bash
cd chapter10/iac/azure
cp terraform.tfvars.example terraform.tfvars   # set github_repository to your fork
tofu init && tofu plan -out ch10.plan && tofu apply ch10.plan
```

1.1 **Kubeconfig** (Entra ID authentication, no local accounts):

```bash
for c in mgmt nonprod prod; do
  az aks get-credentials -g gitops-ch10-rg -n aks-ch10-$c --overwrite-existing
done
kubelogin convert-kubeconfig -l azurecli
```

1.2 **Fill the placeholders in your fork** and commit them:

```bash
export BASE_DOMAIN=example.org ACME_EMAIL=you@example.org
export TEAM_GROUP_OBJECT_ID=$(az ad group show -g "weather-team" --query id -o tsv)
export GITHUB_REPO_URL=https://github.com/<you>/Implementing-GitOps-with-Kubernetes-Second-Edition.git
./chapter10/scripts/render-placeholders.sh
git checkout -b ch10-setup && git add chapter10 && git commit -m "ch10: environment values"
git push -u origin ch10-setup     # open a PR and merge it to main
```

1.3 **Secrets** (never in Git, never in a pipeline):

```bash
KV=$(tofu -chdir=chapter10/iac/azure output -raw key_vault_name)
for env in dev staging prod; do
  az keyvault secret set --vault-name "$KV" -n weather-api-key-$env --value "<weatherapi.com key>"
done
# Fine-grained PAT on your fork: Contents + Pull requests read/write
az keyvault secret set --vault-name "$KV" -n kargo-github-token --value "<token>"
```

1.4 **CI variables** (Settings > Secrets and variables > Actions > Variables):
`AZURE_CLIENT_ID` (output `ci_client_id`), `AZURE_TENANT_ID`,
`AZURE_SUBSCRIPTION_ID`, `ACR_NAME`. Copy `chapter10/ci/.github/workflows/*`
to `.github/workflows/` and push to main: the first image, `3.0.<run>`, is
built, scanned, pushed and signed.

> **First tag.** The overlays start at `newTag: 3.0.0`, which CI never
> produces (it publishes `3.0.<run number>`). Until Kargo promotes the first
> real tag, `weather-*` pods show `ImagePullBackOff`: dev and staging recover
> automatically, prod after step 3.3.
>
> **Pin actions by SHA.** In your fork, replace each `uses: …@vN` with the
> commit SHA of that release, for example
> `gh api repos/aquasecurity/trivy-action/git/ref/tags/v0.36.0 --jq .object.sha`.

### 2. Bootstrap the hub (the only `kubectl apply` of the chapter)

```bash
kubectl config use-context aks-ch10-mgmt
kubectl apply -k chapter10/platform/hub --server-side --force-conflicts
# Wait for the CRDs, then apply again so the Applications and ApplicationSets land
kubectl -n argocd rollout status deploy/argocd-applicationset-controller
kubectl apply -k chapter10/platform/hub --server-side --force-conflicts
```

From now on Argo CD reconciles `chapter10/platform/hub` itself
(`argocd-hub` Application). Every later change is a pull request.

2.1 **UI and CLI** (no public endpoint):

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443 &
argocd admin initial-password -n argocd
argocd login localhost:8080 --username admin --insecure
kubectl -n argocd delete secret argocd-initial-admin-secret   # after changing the password
```

2.2 **Watch the estate assemble**:

```bash
argocd app list -l layer=platform
argocd app list -l layer=application
```

Expected: one Application per add-on and cluster (`cert-manager-aks-ch10-nonprod`,
`kargo-in-cluster`, …), `platform-config-*`, `tenant-weather-{dev,staging,prod}`,
`weather-{dev,staging,prod}` and `kargo-weather`.

2.3 **Kargo admin secret** (one-time, before the Kargo Application can become healthy):

```bash
PASS=$(openssl rand -base64 24)
kubectl create namespace kargo --dry-run=client -o yaml | kubectl apply -f -
kubectl -n kargo create secret generic kargo-api-admin \
  --from-literal=ADMIN_ACCOUNT_PASSWORD_HASH="$(kargo hash-password --password "$PASS")" \
  --from-literal=ADMIN_ACCOUNT_TOKEN_SIGNING_KEY="$(openssl rand -base64 29 | tr -d '=+/' | cut -c1-32)"
echo "Kargo admin password: $PASS"
kubectl -n kargo port-forward svc/kargo-api 8081:443 &
```

2.4 **DNS** for each environment's Gateway (one public IP per environment):

```bash
for ctx in aks-ch10-nonprod aks-ch10-prod; do
  kubectl --context $ctx get gateway -A -o custom-columns=NS:.metadata.namespace,IP:.status.addresses[0].value
done
# Create A records weather-dev / weather-staging / weather-prod.<your-domain>
# pointing at those IPs. cert-manager then completes the HTTP-01 challenge.
```

### 3. From commit to production

```bash
# 3.1 A code change: merge a PR that touches chapter10/src. CI publishes 3.0.<n>.
# 3.2 Kargo discovers it and promotes it to dev, then staging, automatically:
kargo login https://localhost:8081 --admin --insecure-skip-tls-verify
kargo get freight --project weather
kargo get stages --project weather
# 3.3 Production: start the promotion; Kargo opens a pull request
kargo promote --project weather --stage prod --freight <freight-name>
# 3.4 Approve and merge the PR in GitHub. Kargo waits, then syncs weather-prod.
kubectl argo rollouts get rollout weather-app -n weather-prod --watch \
  --context aks-ch10-prod
```

3.5 **See a canary fail** (staging): set `FAULT_ERROR_RATE=0.2` in
`envs/staging/kustomization.yaml`, merge, and generate traffic **through the
Gateway** so that it is split between stable and canary (the in-cluster
`weather-app` Service only reaches the stable version during a canary):

```bash
kubectl kustomize chapter10/ops/load-test \
  | sed "s#http://weather-app#https://weather-staging.$BASE_DOMAIN#" \
  | kubectl apply -n weather-staging --context aks-ch10-nonprod -f -
kubectl argo rollouts get rollout weather-app -n weather-staging --watch --context aks-ch10-nonprod
```

The analysis fails, the rollout aborts and traffic returns to stable. Revert
the change with another pull request.

### 4. Operate

4.1 **Load test and autoscaling**:

```bash
kubectl apply -k chapter10/ops/load-test -n weather-staging --context aks-ch10-nonprod
kubectl get hpa weather-app -n weather-staging -w --context aks-ch10-nonprod
kubectl logs -f job/weather-load-test -n weather-staging --context aks-ch10-nonprod
```

4.2 **VPA recommendation**:

```bash
kubectl get vpa weather-app -n weather-staging --context aks-ch10-nonprod \
  -o jsonpath='{.status.recommendation.containerRecommendations[0]}'
```

4.3 **Access checks** (read-only for the team group, no port-forward in prod):

```bash
kubectl auth can-i delete pods -n weather-prod --as=someone --as-group="$TEAM_GROUP_OBJECT_ID" --context aks-ch10-prod   # no
kubectl auth can-i get pods    -n weather-prod --as=someone --as-group="$TEAM_GROUP_OBJECT_ID" --context aks-ch10-prod   # yes
kubectl auth can-i create pods/portforward -n weather-dev --as=someone --as-group="$TEAM_GROUP_OBJECT_ID" --context aks-ch10-nonprod  # yes
```

### 5. Rebuild a cluster from Git (disaster-recovery drill)

```bash
time tofu -chdir=chapter10/iac/azure apply -replace='azurerm_kubernetes_cluster.this["nonprod"]'
az aks get-credentials -g gitops-ch10-rg -n aks-ch10-nonprod --overwrite-existing
kubelogin convert-kubeconfig -l azurecli
./chapter10/scripts/register-cluster.sh nonprod   # new endpoint and CA
git checkout -b dr-nonprod && git commit -am "ch10: re-register aks-ch10-nonprod" && git push -u origin dr-nonprod   # merge the PR
# Argo CD reinstalls add-ons, tenants and both environments; ESO refetches
# the secrets; the cache starts empty by design.
```

The federated credentials for `weather-dev` and `weather-staging` follow the
new cluster's OIDC issuer automatically, because they depend on the cluster in
OpenTofu. Update the DNS records (step 2.4) if the Gateway IPs changed, and
record the elapsed time: that is your measured recovery time.

---

## Adding an EKS production cluster (delta)

1. Create the cluster with `chapter08/iac/aws` (or your own module), with an
   OIDC provider and an access entry for the hub's role as in
   `chapter12/hub/iac`.
2. Fill `platform/hub/clusters/eks-ch10-prod.yaml` and uncomment it in
   `platform/hub/clusters/kustomization.yaml`.
3. Add `values-aws.yaml` files where an add-on needs one (for example
   service annotations for the AWS Load Balancer Controller in
   `addons/values/envoy-gateway/`).
4. Create `apps/weather/envs/prod-aws/` with `cluster: eks-ch10-prod`, an
   ECR image, `CLOUD_PROVIDER=aws`, and an ESO `SecretStore` for AWS Secrets
   Manager with EKS Pod Identity (see `chapter12/secrets/external-secrets/stores/aws`).
5. Add a `prod-aws` Stage to `promotion/kargo/stages.yaml` that takes Freight
   from `staging`.

The base, the components, the ApplicationSets and the Kargo tasks are unchanged.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| cert-manager does not issue for the Gateway | cert-manager started before the Gateway API CRDs existed | `kubectl -n cert-manager rollout restart deploy/cert-manager` |
| `weather-*` Applications `Unknown`, cluster not found | Cluster Secret still has placeholders | Run `render-placeholders.sh`, commit, push |
| Argo CD: `failed to get token` for nonprod/prod | Workload ID label/annotation missing on Argo CD pods, or federated credential missing | Check `install/workload-identity*.yaml`, `tofu output argocd_hub_client_id` |
| Kargo Warehouse shows no Freight | Kargo controller lacks AcrPull or the Workload ID annotation | `kubectl -n kargo get sa kargo-controller -o yaml`; check `id-ch10-kargo` role assignment |
| Kargo promotion fails at `git-push` | Token lacks Contents write, or repo URL in `git-credentials.yaml` is not your fork | Rotate the Key Vault secret; re-run `render-placeholders.sh` |
| Canary never progresses past the first step | Analysis returns no data | Check the PodMonitor and that Prometheus has `http_requests_total` with `rollouts_pod_template_hash` |
| HTTPRoute weights flip back to 100/0 | Argo CD reverting the plugin's changes | Confirm the `ignoreDifferences` customization in `argocd-cm` and `RespectIgnoreDifferences=true` |
| Pods rejected with `violates PodSecurity "restricted"` | Workload not compliant | Fix the pod spec; do not relax the namespace label |

---

## Cleaning up

```bash
tofu -chdir=chapter10/iac/azure destroy
```

Key Vault is soft-deleted for seven days; purge it with
`az keyvault purge -n <name>` if you need the name again.

---

## Note on open Dependabot branches

Dependabot branches opened against `old_chapter11_is_now_chapter10/Step-01`
before this restructuring now point at a path that moved to
`chapter10/first_edition/real-world-projects/Step-01`. Close them; the
first-edition code is kept for reference only.
