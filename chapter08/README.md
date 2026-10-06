# Chapter 8. Multi-Cloud GitOps: Azure and AWS

Companion code for *Implementing GitOps with Kubernetes, 2nd Edition*.

The chapter text stays at the level of concepts, decisions and trade-offs. **The
complete step-by-step walkthrough lives here**, so that you can follow it at a
terminal without turning pages, and so it can be corrected as the two platforms
move.

---

## What changed since the first edition

The first edition of this chapter (`chapter09` in the first-edition repository)
deployed the sample application with **push-based CI/CD**: an Azure DevOps agent
ran `KubernetesManifest@0` against AKS, and AWS CodeBuild drove EKS. A pipeline
held cluster credentials and applied manifests directly.

This edition inverts that. CI builds an image and stops. **An agent inside each
cluster pulls the desired state and reconciles it**, using the Azure-managed
`microsoft.flux` extension on AKS, and the Amazon EKS capability for Argo CD on
EKS. Nothing outside the cluster holds cluster credentials.

| | First edition | Second edition |
|---|---|---|
| Deployment model | push (pipeline applies) | pull (in-cluster agent reconciles) |
| Azure CD | Azure DevOps `KubernetesManifest@0` | `microsoft.flux` extension + `fluxConfigurations` |
| AWS CD | CodeBuild + `kubectl` | EKS capability for Argo CD (AWS-managed) |
| CI identity | service connection secret, access keys | GitHub OIDC federation, no stored secret |
| Registry pull | `imagePullSecret` in the cluster | AKS kubelet identity (`AcrPull`) / EKS node role |
| Workload identity | not used | Entra Workload ID / EKS Pod Identity |
| Image reference | `:latest`, mutable tags | immutable tags, digest pinned in Git |
| Manifests | two divergent copies (`manifests/`, `deployment/`) | one Kustomize base + per-cloud overlays |
| Kubernetes | 1.29 (out of support) | 1.34 |
| Providers | `azurerm ~> 3`, `aws ~> 5` | `azurerm ~> 4`, `aws ~> 6` |
| Base image | `node:14` (EOL) | `node:22-alpine`, non-root, read-only rootfs |

The legacy pipelines are preserved under `ci/legacy/` with their deploy stages
removed, so you can see exactly which part of an existing pipeline GitOps
replaces.

---

## Layout

```
chapter08/
├── src/                     Sample application (weather-app 2.0)
├── iac/
│   ├── azure/               Resource group, ACR, AKS, Flux extension, CI identity
│   └── aws/                 VPC, ECR, EKS, Pod Identity, Argo CD capability
├── gitops/
│   ├── base/                Portable manifests, no provider names anywhere
│   └── overlays/
│       ├── azure/           ACR image, Entra Workload ID wiring
│       └── aws/             ECR image, Pod Identity wiring
├── flux/                    Git and OCI sources, image automation, alerts (Azure)
├── argocd/                  AppProject, Application, multi-cloud ApplicationSet (AWS)
├── ci/
│   ├── .github/workflows/   Keyless build workflows (copy to the repo root)
│   └── legacy/              Azure Pipelines and CodeBuild, deploy stages removed
└── observability/           Portable Prometheus rules for both clouds
```

> Move `ci/.github/workflows/*` to `.github/workflows/` at the repository root,
> because GitHub only reads workflows from there. They live under `ci/` here to keep the
> chapter self-contained.

---

## Prerequisites

| Tool | Minimum | Check |
|---|---|---|
| Azure CLI | 2.65 | `az version` |
| AWS CLI | 2.20 | `aws --version` |
| GitHub CLI | 2.60 | `gh --version` |
| Terraform *or* OpenTofu | 1.9 | `terraform version` / `tofu version` |
| kubectl | within one minor of the cluster | `kubectl version --client` |
| Flux CLI | 2.7 | `flux --version` |
| Argo CD CLI | 3.x | `argocd version --client` |
| kustomize | 5.x | `kustomize version` |

> **A pip-installed Azure CLI can drift out of date silently.** If `az` was
> installed with `pip install azure-cli` rather than the official installer,
> `pip install --upgrade azure-cli` before you start. An old `azure-cli-core`
> pins an old `azure-mgmt-core`, and `az k8s-extension` (auto-installed in step
> 1.2) will fail to import with `cannot import name 'get_arm_endpoints'` on
> anything before `azure-mgmt-core` 1.5. Also remove the `aks-preview`
> extension if you have an old copy of it installed (`az extension remove
> --name aks-preview`); a stale beta build pins a retired preview API version
> and every `az aks`/`az role assignment` call against the cluster fails with
> `NoRegisteredProviderFound`.

Also required:

- An Azure subscription with permission to create role assignments (**Owner** or
  **User Access Administrator**, since `Contributor` alone cannot grant `AcrPull`).
- **vCPU quota for the node pool's VM size in your chosen region.** `node_vm_size`
  defaults to `Standard_D2s_v4`; check `az vm list-usage --location <region> -o
  table` first if you change it; free/trial and student subscriptions
  frequently have 0 quota left for `v5` families in some regions.
- An AWS account with **AWS IAM Identity Center enabled**, and a group to map to
  the Argo CD `ADMIN` role. Identity Center is the only SSO provider the Argo CD
  capability supports. The capability configuration references your Identity
  Center instance ARN, and the module exposes `idc_region` separately from the
  cluster region, so keep them aligned unless you have a reason not to.
- A GitHub repository you can push to, and permission to create an OIDC provider
  in the AWS account (once per account). **A private repository works, but
  needs two extra steps** — see the callout in 1.1 and 1.2.

Register the Azure providers once per subscription:

```bash
az provider register --namespace Microsoft.ContainerService
az provider register --namespace Microsoft.KubernetesConfiguration
```

> **Cost.** This walkthrough provisions an AKS cluster, an EKS cluster, two
> registries, a NAT gateway and two monitoring workspaces. The NAT gateway and the
> EKS control plane bill per hour regardless of use. Follow *Cleaning up* the same
> day you finish.

---

## Part 1. Azure: AKS with the Flux extension

### 1.1 Provision

```bash
cd chapter08/iac/azure
az login
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)

cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars        # set github_repository and gitops_repository_url

terraform init
terraform plan -out azureplan
terraform apply azureplan
```

> **Private repository?** Set `gitops_auth_secret_name` in `terraform.tfvars`
> (a name of your choosing, e.g. `gitops-ch08-auth`) *before* applying, then
> create that Kubernetes secret after the cluster exists — see the callout at
> the end of 1.2. Without it, the `GitRepository` Flux creates in 1.2 fails
> with `authentication required: Repository not found`, because the example
> assumes the public template repository and configures no Git credentials.
>
> **GitHub "immutable subject claims" enabled?** Check with
> `gh api /repos/<owner>/<repo>/actions/oidc/customization/sub --jq
> .sub_claim_prefix`. A non-empty result means GitHub replaces `owner/repo`
> with `owner@ownerId/repo@repoId` in the OIDC subject it presents, so copy
> that value into `github_oidc_subject_prefix` before applying. Otherwise the
> federated credential Terraform registers in 1.1 will never match what GitHub
> actually sends, and `ch08-build-azure` fails at the `azure/login` step with
> `AADSTS700213: No matching federated identity record found`.

Roughly 10 minutes. Record the outputs:

```bash
terraform output
ACR=$(terraform output -raw acr_login_server)
CI_CLIENT_ID=$(terraform output -raw ci_client_id)
```

`local_account_disabled = true` means there is no cluster-local admin
certificate; access is granted through Entra and Azure RBAC. Give yourself the
cluster admin role, then fetch credentials:

```bash
RG=$(terraform output -raw resource_group_name)
CLUSTER=$(terraform output -raw cluster_name)

az role assignment create \
  --assignee "$(az ad signed-in-user show --query id -o tsv)" \
  --role "Azure Kubernetes Service RBAC Cluster Admin" \
  --scope "$(az aks show -g "$RG" -n "$CLUSTER" --query id -o tsv)"

az aks get-credentials --resource-group "$RG" --name "$CLUSTER"
kubectl get nodes
```

> **Re-provisioning from scratch (e.g. after `terraform destroy`)?** `ACR`,
> `CI_CLIENT_ID`, and the cluster's OIDC issuer are all regenerated with new
> random/GUID values — nothing here is stable across a rebuild. Three things
> outside Terraform's state do **not** carry over and must be redone every
> time, not just the first time:
> - The RBAC role assignment above (Owner/Contributor at the subscription
>   level does **not** include Kubernetes data-plane access once
>   `local_account_disabled = true`; `kubectl` fails with `Forbidden ... User
>   does not have access to the resource in Azure` until you re-run it).
> - The `gitops_auth_secret_name` secret for a private repo (1.2) — Azure
>   does not persist or recreate its contents.
> - The `ACR_NAME` and `AZURE_CLIENT_ID` repository variables in 1.3, and the
>   `newName`/`newTag` in the overlay in 1.4 — a stale ACR name in the
>   overlay produces `ImagePullBackOff`/`ErrImagePull` with no Terraform or
>   Flux error to point at it.

### 1.2 Confirm Azure installed and configured Flux

Nothing was installed by hand. `iac/azure/flux.tf` declared the extension and
the Flux configuration, and Azure reconciled them:

```bash
az k8s-extension show \
  --resource-group "$RG" --cluster-name "$CLUSTER" \
  --cluster-type managedClusters --name flux \
  --query "{version:version, provisioningState:provisioningState}" -o table

kubectl get pods -n flux-system
flux get all
```

You should see the source, kustomize, helm and notification controllers, which
the extension installs by default, plus the image-reflector and image-automation
controllers, which are opt-in and were enabled in `flux.tf`. You should also see
a `GitRepository` named `gitops-ch08` and a `Kustomization` named
`gitops-ch08-apps`. Azure names cluster objects
`<fluxConfiguration>-<kustomization>`, which is the name to use with the Flux CLI.

> **Upgrading from the first edition.** Extension **1.23.0 (June 2026) removed the
> deprecated Flux beta APIs**: `source.toolkit.fluxcd.io/v1beta1` and `v1beta2`,
> `kustomize.toolkit.fluxcd.io/v1beta1` and `v1beta2`,
> `helm.toolkit.fluxcd.io/v2beta1` and `v2beta2`, and the `v1beta1` notification
> and image APIs. Manifests written for the first edition will not reconcile.
> Everything in `flux/` uses current APIs: `source/v1`, `kustomize/v1`, `helm/v2`
> and `image/v1` (promoted to stable in Flux 2.7). Note that the notification
> `Alert` and `Provider` kinds are still `v1beta3`, which is their current
> version, not a deprecated one, so they need no migration.

> **Private repository, continued.** If you set `gitops_auth_secret_name`,
> Terraform *may* pre-create an empty placeholder secret with that name in
> `flux-system` (owned by the `FluxConfig` resource) — but after any rebuild
> (a fresh `terraform apply`, or a prior `terraform destroy`) it is more often
> simply **absent**, not empty. Use `create ... --dry-run=client -o yaml |
> apply -f -` rather than `kubectl patch`: `patch` only works when the secret
> already exists and fails with `NotFound` otherwise, while this form works
> either way. Populate it with a fine-grained token scoped to **only this
> repository**, permission **Contents: Read-only** — generate it at
> <https://github.com/settings/tokens?type=beta>, and type it directly into
> your own terminal rather than pasting it anywhere else; a PAT pasted into a
> chat, ticket or log should be treated as compromised and revoked:
>
> ```bash
> kubectl create secret generic gitops-ch08-auth -n flux-system \
>   --from-literal=username=git \
>   --from-literal=password='<your PAT>' \
>   --dry-run=client -o yaml | kubectl apply -f -
> flux reconcile source git gitops-ch08 -n flux-system
> ```
>
> `kubectl get gitrepository gitops-ch08 -n flux-system` should flip to
> `READY: True`. If it still reports `authentication required`, the token is
> the usual culprit, not the wiring — verify it first with
> `curl -o /dev/null -w '%{http_code}\n' -H "Authorization: token <PAT>"
> https://api.github.com/repos/<owner>/<repo>` (expect `200`).

### 1.3 Build the image without a stored secret

Set these as **repository variables**, not secrets, since none of them is sensitive:

```bash
gh variable set AZURE_CLIENT_ID       --body "$CI_CLIENT_ID"
gh variable set AZURE_TENANT_ID       --body "$(az account show --query tenantId -o tsv)"
gh variable set AZURE_SUBSCRIPTION_ID --body "$ARM_SUBSCRIPTION_ID"
gh variable set ACR_NAME              --body "${ACR%%.*}"
```

Push a change under `chapter08/src/` and watch `ch08-build-azure` run. GitHub presents
a short-lived OIDC token; Entra validates it against the federated credential
subject and returns an access token scoped to `AcrPush`. There is no client
secret and no registry password in the repository.

### 1.4 Point the overlay at your registry and let the cluster pull

Use a tag `ch08-build-azure` actually pushed (check with `az acr repository
show-tags --name "${ACR%%.*}" --repository weather-app -o table`), not the
placeholder below — a tag that isn't in the registry produces a silent
`ImagePullBackOff`, not a Terraform or Flux error.

```bash
cd ../../gitops/overlays/azure
kustomize edit set image "weather-app=${ACR}/weather-app:2.0.1"
git add -A && git commit -m "chore(ch08): azure overlay image" && git push
```

Then watch the cluster converge on its own:

```bash
flux reconcile kustomization gitops-ch08-apps --with-source -n flux-system
kubectl -n weather-app get deploy,pod
kubectl -n weather-app port-forward svc/weather-app 8080:80
```

The page reports `served from: azure`.

### 1.5 See reconciliation actually reconcile

This is the behaviour the first edition could not demonstrate, because a pipeline
that has already exited cannot notice anything:

```bash
kubectl -n weather-app scale deploy/weather-app --replicas=5
kubectl -n weather-app get deploy weather-app -w      # returns to 2
```

Flux detects the divergence and restores the state recorded in Git. Compare
`kubectl rollout undo`, which changes the cluster but leaves Git, and therefore
the next reconciliation, unchanged.

---

## Part 2. AWS: EKS with the managed Argo CD capability

### 2.1 One-time account setup

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com

aws sso-admin list-instances --query 'Instances[0].InstanceArn' --output text
```

Note the region the Identity Center instance is in and use it for `region`.

### 2.2 Provision

```bash
cd chapter08/iac/aws
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars    # region, idc_admin_group_display_name, github_repository

terraform init
terraform plan -out awsplan
terraform apply awsplan
```

Expect 15 to 20 minutes; the EKS control plane and node group dominate. Then:

```bash
eval "$(terraform output -raw update_kubeconfig_command)"
kubectl get nodes

ECR=$(terraform output -raw ecr_repository_url)
ACCOUNT_ID=$(terraform output -raw account_id)
CLUSTER_ARN=$(terraform output -raw cluster_arn)
```

### 2.3 Confirm the capability

```bash
aws eks list-capabilities --cluster-name eks-gitops-ch08
aws eks describe-capability --cluster-name eks-gitops-ch08 --capability-name argocd
```

Note what is *not* there: no `argocd-server`, `argocd-repo-server` or
`argocd-application-controller` pods in your cluster. AWS runs the control plane
outside it and handles scaling, upgrades, high availability, SSO and ECR token
refresh. Sign in through the AWS console using an Identity Center identity in the
group you mapped to `ADMIN`.

If the capability reports permission errors reaching the cluster, associate the
access policy:

```bash
aws eks associate-access-policy \
  --cluster-name eks-gitops-ch08 \
  --principal-arn "$(terraform output -raw argocd_capability_role_arn)" \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster
```

### 2.4 Register the cluster and create the Application

```bash
cd ../../argocd
sed -e "s/ACCOUNT_ID/${ACCOUNT_ID}/" cluster-secret-example.yaml | kubectl apply -f -
kubectl apply -f appproject.yaml
kubectl apply -f application-aws.yaml
```

Two capability-specific details matter and will bite you otherwise:

- **Clusters are addressed by ARN, not by API server URL.** A manifest carrying
  `server: https://...eks.amazonaws.com` will not resolve. The local cluster is
  not auto-registered either, so register it by ARN like any other.
- **All `Application`, `ApplicationSet` and `AppProject` objects must live in the
  single namespace configured when the capability was created** (`argocd` here).
  CLI commands need the namespace prefix:

```bash
argocd app get argocd/weather-app-aws
argocd app sync argocd/weather-app-aws
```

`argocd login` and `argocd admin` are unsupported; authenticate with a token.

### 2.5 Point the overlay at your registry

```bash
cd ../gitops/overlays/aws
kustomize edit set image "weather-app=${ECR}:2.0.1"
git add -A && git commit -m "chore(ch08): aws overlay image" && git push
```

```bash
argocd app sync argocd/weather-app-aws
kubectl -n weather-app port-forward svc/weather-app 8080:80
```

The page reports `served from: aws`, produced by the same base manifests and a
different overlay.

### 2.6 The multi-cloud fleet view

The capability targets **EKS clusters only**, so the AKS cluster cannot be
registered with it. To see the fleet view across both clouds you need either
self-managed Argo CD (Chapter 4) or an AKS cluster attached to Azure Arc and
driven from Azure. With two or more EKS clusters registered, the ApplicationSet
below generates one Application per cluster from the `cloud` label:

```bash
kubectl apply -f ../../argocd/applicationset-multicloud.yaml
argocd app list -o wide
```

One definition generates one `Application` per registered cluster, and the
`cloud` label selects the overlay. Adding a third provider means registering a
cluster and adding an overlay directory; the ApplicationSet does not change.

> Adding a third provider means registering a cluster and adding an overlay
> directory. The ApplicationSet itself does not change.

---

## Part 3. Verify, then tear down

### Verify

```bash
# Both overlays render, and the base contains no provider-specific values
kustomize build gitops/overlays/azure | grep -E 'image:|cloud:'
kustomize build gitops/overlays/aws   | grep -E 'image:|cloud:'
grep -rniE 'azurerm|\.amazonaws\.com|azurecr\.io' gitops/base/ && echo "LEAK" || echo "base is portable"

# Reconciliation health
flux get all -A                     # Azure
argocd app list                     # AWS
```

Load the alerting rules from `observability/`. Amazon Managed Prometheus accepts
the rule-group YAML directly; Azure Monitor managed Prometheus needs it converted
to a `Microsoft.AlertsManagement/prometheusRuleGroups` resource, and Microsoft's
`az-prom-rules-converter` does that, so the expressions are still written once.
Read `observability/README.md` first: the `cloud` label the rules group by has to
be added as an external label at collection time, not by Kustomize.

### Cleaning up

Do this the same day. Delete the capability before the cluster, or the capability
deletion can be left orphaned:

```bash
cd chapter08/iac/aws
terraform destroy -auto-approve

cd ../azure
terraform destroy -auto-approve
```

Then confirm in both consoles that the resource group, the VPC, the NAT gateway
and both registries are gone. Also delete images from ACR and ECR, because
repositories with images can block destruction.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Kustomization` stuck `not ready` | overlay references a nonexistent path or an invalid patch | `flux get kustomizations`, then `kustomize build` the overlay locally |
| `ImagePullBackOff`/`ErrImagePull` on AKS | either the `AcrPull` role assignment has not yet propagated, **or** the overlay's `newName` still points at an ACR that no longer exists (common after re-provisioning: the ACR name is a random suffix, regenerated on every `terraform apply` from empty state) | wait a few minutes and verify `az role assignment list --scope <acr-id>`; also check `terraform output -raw acr_login_server` against `newName` in `gitops/overlays/azure/kustomization.yaml` |
| Flux CRD errors mentioning `v1beta1` | manifests use APIs removed in extension 1.23.0 | migrate to `source/v1`, `kustomize/v1`, `helm/v2` |
| Argo CD cannot reach the cluster | destination uses an API URL, not an ARN | use the cluster ARN; check the EKS access entry |
| `Application` ignored | created outside the capability's namespace | move it into the configured namespace |
| GitHub Actions `AADSTS700213` / `AccessDenied` on OIDC | federated subject does not match the branch, **or** the repository has immutable OIDC subject claims enabled | check the `subject` in `ci-identity.tf` / `identity.tf` against the workflow ref; also check `gh api /repos/<owner>/<repo>/actions/oidc/customization/sub --jq .sub_claim_prefix` and set `github_oidc_subject_prefix` if it returns one |
| GitHub Actions `AADSTS700016: Application with identifier '***' was not found in the directory` | the `AZURE_CLIENT_ID` repository variable still names a CI identity that no longer exists — almost always because the cluster was rebuilt from scratch, which creates a brand new CI identity with a new client id | `gh variable set AZURE_CLIENT_ID --body "$(terraform output -raw ci_client_id)"`, then re-run the workflow |
| `Kustomization`/`FluxConfig` `Missing required argument` for `azure_active_directory_role_based_access_control` | azurerm v4 requires `tenant_id` (or `admin_group_object_ids`) explicitly; it is no longer inferred | add a `data "azurerm_client_config" "current" {}` and set `tenant_id = data.azurerm_client_config.current.tenant_id` |
| `GitRepository` reports `authentication required: Repository not found` | `gitops_repository_url` points at a private repo with no Flux credentials configured, **or** it did once but the whole cluster/Flux config was re-provisioned since (the secret is not Terraform state and does not come back on its own) | set `gitops_auth_secret_name` and populate the secret — see the callout at the end of 1.2; redo this every time the cluster is rebuilt from scratch |
| `az` command fails with `NoRegisteredProviderFound` for an API version not in the supported list | a stale/beta `aks-preview` CLI extension is forcing a retired preview API version | `az extension remove --name aks-preview` |
| `az k8s-extension show` fails with `cannot import name 'get_arm_endpoints'` | Azure CLI installed via `pip` has drifted out of date | `pip install --upgrade azure-cli` |
| `terraform apply` fails with `ErrCode_InsufficientVCPUQuota` on the node pool | subscription has 0 vCPU quota for that VM family in the region (common for `v5` families on trial/student subscriptions) | `az vm list-usage --location <region> -o table`, then pick a `node_vm_size` with headroom, or request a quota increase |
| `terraform apply` fails granting `AcrPull` | account lacks role-assignment rights | need Owner or User Access Administrator |
| `kubectl get nodes` fails with `Forbidden ... User does not have access to the resource in Azure` | `local_account_disabled = true` makes Kubernetes API access an Azure RBAC **data-plane** permission, separate from ARM roles; being subscription **Owner does not include it** | run the `az role assignment create ... "Azure Kubernetes Service RBAC Cluster Admin"` command in 1.1, then wait a minute or two for propagation |
| Azure build fails with an authorization error | `az acr build` needs `scheduleRun/action`, which `AcrPush` does not include | build on the runner and push (what the workflow does), or add the Container Registry Tasks Contributor role |
| Image automation runs but changes nothing | the `Setters` strategy only rewrites lines with an `$imagepolicy` marker | keep the markers in `gitops/overlays/azure/kustomization.yaml` |
| `Kustomization` won't pick up a new commit even after `flux reconcile --with-source`, `GitRepository` already shows the new revision | `spec.wait: true` + `force: false` (Azure's default) blocks a *running* reconcile — one stuck health-checking a bad prior revision — until its own timeout elapses; a new request just queues behind it | `kubectl -n flux-system delete pod -l app=kustomize-controller` to abort the stuck attempt immediately, rather than waiting out the `timeout_in_seconds` |
| `OCIRepository` reports no matching signatures | the artifact was pushed but not signed | the `cosign sign` step in `ch08-build-azure.yml` must run after `flux push artifact` |
| `{{ $labels.cloud }}` renders blank in an alert | no `cloud` external label configured | see `observability/README.md` |
| Argo CD capability creation fails | Identity Center not enabled, or wrong region | enable Identity Center; create the capability in its region |

---

## References

Accessed 9 August 2026.

- Flux (GitOps) extension release notes: <https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/flux-gitops-release-notes>
- Application deployments with GitOps (Flux v2): <https://learn.microsoft.com/en-us/azure/azure-arc/kubernetes/conceptual-gitops-flux2>
- Supported Kubernetes versions in AKS: <https://learn.microsoft.com/en-us/azure/aks/supported-kubernetes-versions>
- Microsoft Entra Workload ID on AKS: <https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview>
- Announcing Amazon EKS Capabilities: <https://aws.amazon.com/about-aws/whats-new/2025/11/amazon-eks-capabilities>
- Comparing EKS Capability for Argo CD to self-managed Argo CD: <https://docs.aws.amazon.com/eks/latest/userguide/argocd-comparison.html>
- Streamlining GitOps with the Amazon EKS capability for Argo CD: <https://aws.amazon.com/blogs/containers/deep-dive-streamlining-gitops-with-amazon-eks-capability-for-argo-cd/>
- `terraform-aws-modules/eks` EKS capabilities example: <https://github.com/terraform-aws-modules/terraform-aws-eks/tree/v21.24.0/examples/eks-capabilities>
- Amazon EKS version support: <https://endoflife.date/amazon-eks>
- AzureRM provider 4.0 upgrade guide: <https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/4.0-upgrade-guide>
- Authenticate to Azure from GitHub Actions with OIDC: <https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure-openid-connect>
- `aws-actions/configure-aws-credentials`: <https://github.com/aws-actions/configure-aws-credentials>
