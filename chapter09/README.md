# Chapter 9. GitOps for Infrastructure Automation: Terraform, OpenTofu and Flux CD

Companion code for *Implementing GitOps with Kubernetes, 2nd Edition*.

Chapter 8 ran infrastructure code **before** the cluster existed, from a
terminal or a CI job, to stand up AKS and EKS. This chapter does the opposite:
it puts the infrastructure code **inside** the cluster's reconciliation loop, so
that a virtual network and a storage account converge the same way a Deployment
does, and so that a change made in the portal is noticed rather than
discovered.

The chapter text carries the reasoning. **The complete walkthrough is here**, so
that you can follow it at a terminal without turning pages, and so that it can
be corrected as the projects move.

---

## What changed since the first edition

The first edition of this chapter is `chapter10` in the
[first-edition repository](https://github.com/PacktPublishing/Implementing-GitOps-with-Kubernetes).

| | First edition | Second edition |
|---|---|---|
| IaC tool | Terraform 1.7.5 / 1.8.1 | OpenTofu 1.12.x, with Terraform 1.16.x noted |
| Licensing | not discussed | BUSL 1.1, licensor IBM since 2025; MPL fork covered |
| Controller | TF-Controller (Weaveworks) | Tofu Controller v0.16.5 (`flux-iac`, August 2026) |
| Flux install | `flux bootstrap` from a laptop | `FluxInstance` reconciled by the Flux Operator |
| Flux version | 2.2.3 | 2.7.x (see the version note in `flux/flux-instance.yaml`) |
| Cloud identity | service principal client secret in a Secret | Entra Workload ID federation, no stored secret |
| Runner image | custom build overwriting `terraform`, plus the Azure CLI | stock `tf-runner`, which already ships `tofu`; custom build only when you need a different version |
| Production mode | `approvePlan: auto` everywhere | plan, then an approval that is itself a commit, from a source pinned to a tag |
| State | never mentioned; default cluster Secret | Secret for dev, `azurerm` backend for staging and prod, locking and recovery covered; optional OpenTofu state encryption with Key Vault |
| Environments | `base/` copied byte for byte into `dev/`, `staging/`, `prod/` | one module, three thin roots, inputs per environment |
| Dependencies | none | `dependsOn` plus `writeOutputsToSecret` / `varsFrom` |
| App coupling | none | outputs Secret consumed via `postBuild.substituteFrom` |
| Policy | prose advice only | Checkov and Conftest gates on the pull request |
| Drift | model described, never wired up | `approvePlan: disable`, plus a `Provider` and an `Alert` |
| Kubernetes | AKS 1.28.5 (out of support) | management cluster from Chapter 8, or kind |

---

## Layout

```
chapter09/
├── identity/          Bootstrap: managed identity, federation, state account (run once, by hand)
├── runner/            Optional custom tf-runner image; the stock image already ships tofu
├── flux/              FluxInstance (applied by the CLI) and the Tofu Controller HelmRelease
├── iac/
│   ├── modules/
│   │   ├── network/   Resource group, virtual network, two subnets
│   │   └── data/      Storage account, private endpoint and its private DNS zone
│   ├── azure/
│   │   ├── dev/       network/ and data/ roots; state in a cluster Secret
│   │   ├── staging/   network/ and data/ roots; remote state, auto-applied
│   │   └── prod/      network/ and data/ roots; remote state, manual approval
│   └── aws/dev/       The same pattern on EKS with IRSA
├── terraform/         Custom resources the management cluster reconciles,
│                      plus the tag-pinned infra-modules source for production
├── examples/          Custom resources you apply by hand, and the optional
│                      state encryption example (see examples/README.md)
├── notifications/     Provider and Alert
├── gitops/            Application manifests that consume the infrastructure outputs
├── clusters/mgmt/     What the management cluster reconciles
├── policy/            Checkov configuration and Conftest policies
├── ci/                Pull request gate: fmt, validate, scan, plan, policy
└── first_edition/     Code from the first edition of the book, kept for reference
```

> **Where the workflow is.** The pull request gate is in
> `chapter09/ci/.github/workflows/ch09-iac-policy.yml`. GitHub only reads workflows
> from `.github/workflows/` at the repository root, so it is deliberately **not** active
> in this repository. To run the exercises, work in your own fork (or copy of this
> chapter) and copy it to its root:
>
> ```bash
> mkdir -p .github/workflows
> cp chapter09/ci/.github/workflows/ch09-iac-policy.yml .github/workflows/
> ```
>
> Then create the three repository variables listed at the top of the workflow file,
> and a GitHub environment named `iac-plan` with required reviewers. The `static`
> job (format, validate, Checkov) runs on every pull request with no cloud access.
> The `plan` job, which reads real staging and production state, runs in `iac-plan`
> and waits for a reviewer; the CI identity's federated credential trusts only
> `repo:<owner>/<repo>:environment:iac-plan`.

### What the cluster reconciles, and what it does not

`clusters/mgmt` is the FluxInstance's sync path, so **only what it lists is ever
applied.** It lists four things: the Tofu Controller Kustomization, the
infrastructure Kustomization, the alerts, and the application Kustomization.

`chapter09/terraform` is applied wholesale by the infrastructure Kustomization,
so it holds only objects the management cluster should actually reconcile.
Anything that cannot reach `Ready` on this cluster lives in `examples/` and is
applied by hand — otherwise it would sit unhealthy in the directory that the
application layer depends on.

---

## Prerequisites

* A management cluster. The AKS cluster from Chapter 8 works; so does `kind`,
  though the workload identity steps then have no meaning and you fall back to
  a service principal.
* An Azure subscription in which you can create role assignments.
* `tofu` 1.12 or later (or `terraform` 1.9 or later), `kubectl`, and the Flux
  CLI **2.9 or later** — 2.9 is the release that introduced the plugin system
  used in step 2.
* Docker only if you follow step 3, which most readers should skip.
* **Your own fork of the book repository.** Production approvals are commits,
  so the cluster has to sync from a repository you can push to. Fork it, then
  change `sync.url` in `flux/flux-instance.yaml` and `spec.url` in
  `terraform/infra-modules-source.yaml` to your fork, and create the tag
  production plans from:

  ```bash
  git tag infra-v1.0.0 && git push origin infra-v1.0.0
  ```

  **If that fork is private**, `flux-instance.yaml`'s `sync` block needs a
  `pullSecret` — the operator does not create one the way `flux bootstrap`
  used to. Generate a fine-grained PAT scoped to **only this repository**,
  permission **Contents: Read-only**, at
  <https://github.com/settings/tokens?type=beta> (type it directly into your
  terminal, never into a chat, ticket or log — treat one pasted anywhere else
  as compromised and revoke it), then:

  ```bash
  kubectl create secret generic flux-system-auth -n flux-system \
    --from-literal=username=git \
    --from-literal=password='<your PAT>' \
    --dry-run=client -o yaml | kubectl apply -f -
  ```

  Add `pullSecret: flux-system-auth` next to `url` in `flux-instance.yaml`'s
  `sync` block (see the comment already there) before step 2's
  `flux operator install`.

> **If Chapter 8's cluster is ever rebuilt** (a fresh `terraform apply` from
> empty state, or any `terraform destroy` + `apply`), its OIDC issuer URL
> regenerates along with the ACR name and CI client id covered in that
> chapter's README — nothing about it is stable across a rebuild. Since
> `identity/main.tf` bakes `TF_VAR_oidc_issuer_url` into the `tf-runner`
> federated credential at apply time, a rebuild silently breaks every runner
> pod's ability to get an Azure token, with no error until the next
> reconcile. Re-run step 1 with the new issuer URL whenever you rebuild the
> management cluster:
>
> ```bash
> cd chapter09/identity
> export TF_VAR_oidc_issuer_url=$(az aks show \
>   -g gitops-ch08-rg -n aks-gitops-ch08 \
>   --query oidcIssuerProfile.issuerUrl -o tsv)
> tofu plan -out bootstrap && tofu apply bootstrap
> ```

> **Cost warning.** The custom resources that ship here create **three resource
> groups, three virtual networks, three storage accounts with private endpoints
> and private DNS zones** (dev, staging and prod), plus the state storage
> account from the bootstrap step. Private endpoints are billed per hour per
> endpoint, and production uses zone redundant storage, so it is the expensive
> environment. Production is created only once you approve its plans in
> step 6. Run the teardown at the end and check the portal rather than
> assuming.

---

## Walkthrough

### 1. Bootstrap the identity (once, from a terminal)

Something has to create the identity the runner inside the cluster will use, and
it cannot be that runner. This is the one place in the chapter where OpenTofu
runs outside the loop.

```bash
cd chapter09/identity

export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
export TF_VAR_oidc_issuer_url=$(az aks show \
  -g gitops-ch08-rg -n aks-gitops-ch08 \
  --query oidcIssuerProfile.issuerUrl -o tsv)

# Storage account names are globally unique and you will need this one again
# in step 6, so pick something you can retype rather than a random suffix.
export TF_VAR_state_storage_account_name=gitopstfstate<yourinitials>

# Optional: a read-only identity for the pull request gate in ci/.
# export TF_VAR_github_repository=<owner>/<your-fork>

# Only needed if that fork (or its enterprise/org) has "Use immutable subject
# claims" enabled under Settings > Actions > General. Check with:
#   gh api /repos/<owner>/<your-fork>/actions/oidc/customization/sub --jq .sub_claim_prefix
# If that prints "use_default":true with no sub_claim_prefix, leave this unset.
# export TF_VAR_github_oidc_subject_prefix="repo:<owner>@<ownerId>/<your-fork>@<repoId>"

tofu init
tofu plan -out bootstrap
tofu apply bootstrap
```

Now export the outputs. **Step 4 needs all three of these in the environment**,
so do not skip this:

```bash
export ARM_CLIENT_ID=$(tofu output -raw client_id)
export ARM_TENANT_ID=$(tofu output -raw tenant_id)
export ARM_SUBSCRIPTION_ID=$(tofu output -raw subscription_id)
export STATE_ACCOUNT=$(tofu output -raw state_storage_account_name)
```

The staging and production objects, and the backend settings CI and the
cleanup use, all name that account. Put it in once, everywhere, and commit:

```bash
cd ../..   # repository root
grep -rl REPLACE_WITH_YOUR_STATE_ACCOUNT \
    chapter09/terraform chapter09/iac/azure/staging chapter09/iac/azure/prod \
  | xargs sed -i.bak "s/REPLACE_WITH_YOUR_STATE_ACCOUNT/$STATE_ACCOUNT/g"
find chapter09 -name '*.bak' -delete
git commit -am "chapter09: set state storage account" && git push
```

Scope the `grep` to those three directories, not the whole `chapter09` tree:
a broader sweep also matches this README's own instructional text and
`identity/outputs.tf`'s output description (both contain the literal
placeholder string as documentation), silently baking your real storage
account name into files that were only ever meant to show the generic
placeholder.

That touches `terraform/staging-*.yaml`, `terraform/prod-*.yaml` and
`iac/azure/{staging,prod}/backend.hcl`.

### 2. Install Flux and the Tofu Controller

```bash
flux plugin install operator
flux operator install -f chapter09/flux/flux-instance.yaml
```

Edit `chapter09/flux/tofu-controller.yaml`, replacing
`<managed-identity-client-id>` with `$ARM_CLIENT_ID` from step 1, then commit.

The FluxInstance syncs `chapter09/clusters/mgmt`, which contains a Kustomization
pointing at `chapter09/flux`. That is what applies the `infra-*` namespaces
and the HelmRelease; the namespaces come first because the chart renders a
`tf-runner` service account into every namespace in `allowedNamespaces` and
fails if one is missing. The
infrastructure Kustomization `dependsOn` it, so the `infra.contrib.fluxcd.io`
CRD exists before any `Terraform` object is applied.

```bash
kubectl -n flux-system get kustomization tofu-controller
kubectl -n flux-system get helmrelease tofu-controller
```

### 3. Build the runner image — optional, and usually unnecessary

The published `ghcr.io/flux-iac/tf-runner` image **already contains OpenTofu**.
The project's `runner.Dockerfile` copies the `tofu` binary out of
`ghcr.io/opentofu/opentofu:<version>-minimal`, which for the v0.16.5 line is
OpenTofu 1.12.1. Leave `runner.image` commented out in the HelmRelease and skip
to step 4.

Build your own only when you need a different OpenTofu version, Terraform
instead of OpenTofu, or extra tooling in the runner:

```bash
cd chapter09/runner
export TF_CONTROLLER_VERSION=v0.16.5
export TOFU_VERSION=1.12.9

docker build \
  --build-arg BASE_IMAGE=ghcr.io/flux-iac/tf-runner:${TF_CONTROLLER_VERSION}-base \
  --build-arg TOFU_VERSION=${TOFU_VERSION} \
  -t ghcr.io/<your-org>/tofu-runner:${TF_CONTROLLER_VERSION} .

docker push ghcr.io/<your-org>/tofu-runner:${TF_CONTROLLER_VERSION}
```

Then uncomment `runner.image` in `flux/tofu-controller.yaml`.

### 4. Supply the non-secret environment values

Subscription, tenant and client id are identifiers, not secrets, so they live
in a ConfigMap rather than a Secret. There is no client secret to store.

```bash
# All three were exported at the end of step 1.
kubectl create configmap azure-environment -n flux-system \
  --from-literal=subscription_id=$ARM_SUBSCRIPTION_ID \
  --from-literal=tenant_id=$ARM_TENANT_ID \
  --from-literal=client_id=$ARM_CLIENT_ID
```

Check it before moving on — an empty value here surfaces much later as an
authentication error that points nowhere near the cause:

```bash
kubectl -n flux-system get configmap azure-environment -o jsonpath='{.data}'
```

### 5. Watch the loop run

```bash
kubectl get terraforms.infra.contrib.fluxcd.io -n flux-system -w
```

`dev-network` and `staging-network` plan and apply. `dev-data` and
`staging-data` stay `Unknown` until their network's outputs Secret exists, then
plan and apply in turn. `prod-network` plans and waits for you; `prod-data`
waits for `prod-network`.

```bash
kubectl -n flux-system get secret dev-network-outputs -o yaml
kubectl -n flux-system get secret dev-data-outputs \
  -o jsonpath='{.data.blob_endpoint}' | base64 -d
```

### 6. Approve production

The production objects plan from `infra-modules`, a second source pinned to the
tag `infra-v1.0.0`. That is what lets an approval committed to `main` work:
the plan id is derived from the source revision, and v0.16.5 replans right
before a manual apply and requires the new id to match exactly. With both the
object and its HCL on `main`, the approval commit itself would change the id
and the approval would never match
([flux-iac/tofu-controller#1878](https://github.com/flux-iac/tofu-controller/issues/1878),
fix proposed in [#1890](https://github.com/flux-iac/tofu-controller/pull/1890),
unreleased at the time of writing).

```bash
kubectl -n flux-system get tf/prod-network
# prod-network  Unknown  Plan generated: set approvePlan: "plan-infra-v1.0.0-b8e362c206" to approve this plan.
```

The id above (`b8e362c206`) is illustrative only — it is derived from the
commit the `infra-v1.0.0` tag points to in **your** fork, so yours will be
different. Run the command yourself and copy the id it actually prints; do
not reuse the sample text. (If you re-tag or re-push `infra-v1.0.0`, the id
changes again and any previously-set `approvePlan` stops matching.)

Copy the id exactly, set it as `spec.approvePlan` in
`terraform/prod-network.yaml`, and commit to `main`. The approval is a
reviewable change in Git, not a click. When `prod-network` is `Ready`, do the
same for `prod-data`.

To change production later: merge the HCL change to `main` (staging applies
it), move the tag forward, set `ref.tag` in
`terraform/infra-modules-source.yaml` to the new tag, commit, and approve the
new plan.

### 7. Prove drift detection

Change a setting on a subnet the module manages, then wait one interval:

```bash
az network vnet subnet update \
  -g gitops-dev-rg --vnet-name gitops-dev-vnet \
  -n workload --service-endpoints Microsoft.Storage

kubectl -n flux-system describe tf/dev-network | grep -A5 Drift
```

`dev-network` reports the drift and, because it is in automation mode, removes
the service endpoint again. Do the same against `gitops-prod-vnet` and
`prod-network` reports it, generates a plan, and waits.

Now the counterexample, which is the more instructive of the two:

```bash
az network vnet subnet create \
  -g gitops-dev-rg --vnet-name gitops-dev-vnet \
  -n rogue --address-prefixes 10.10.9.0/24
```

Nothing happens. The subnet is in nobody's state -- the module declares its
subnets as separate `azurerm_subnet` resources, and the virtual network's own
`subnet` attribute is not compared when it is left unset -- so the plan says
there is nothing to change. Drift detection compares what the state records
with the code; it is not an inventory. A resource that was never declared is
invisible to it regardless of where it sits, so it is not the tool for
answering "does anything exist that shouldn't" -- that question belongs to
Azure Policy or a cloud inventory tool, not to this chapter. Delete the rogue
subnet by hand:

```bash
az network vnet subnet delete -g gitops-dev-rg --vnet-name gitops-dev-vnet -n rogue
```

### 8. Tear down

**Stop Flux first, or it will undo your work.** The Terraform objects are owned
by the `infrastructure` Kustomization, and anything you delete with `kubectl`
is recreated from Git at the next interval, along with the cloud resources
behind it.

```bash
flux suspend kustomization weather-app infrastructure
```

Then delete the dependent objects before their dependencies.
`destroyResourcesOnDeletion: true` means the controller runs a destroy and waits
for it before releasing the finalizer, so these commands do not return
immediately:

```bash
kubectl delete -f chapter09/terraform/dev-data.yaml
kubectl delete -f chapter09/terraform/dev-network.yaml
kubectl delete -f chapter09/terraform/staging-data.yaml
kubectl delete -f chapter09/terraform/staging-network.yaml
kubectl get terraforms.infra.contrib.fluxcd.io -n flux-system
```

Leave the controller, both GitRepository objects and the `tf-runner` service
account in place until that last command shows those objects gone. The destroy
is an ordinary reconciliation: it needs the source to fetch the code from and a
runner with an identity to run it, and a finalizer that has lost either waits
forever.

The production objects set `destroyResourcesOnDeletion: false`. Delete them so
the controller stops reconciling them -- this orphans the cloud resources, it
does not destroy them:

```bash
kubectl delete -f chapter09/terraform/prod-data.yaml
kubectl delete -f chapter09/terraform/prod-network.yaml
```

Then destroy production from a terminal, against the remote state, data before
network. The data root's inputs normally come from the outputs Secret, so read
them from the network state instead:

```bash
cd chapter09/iac/azure/prod/network

# Do not skip this: backend.hcl has no use_oidc, so this init authenticates
# with your Azure CLI session instead. If ARM_TENANT_ID and
# ARM_SUBSCRIPTION_ID are still exported from step 1, the Azure CLI fallback
# errors with "Please specify only one of subscription and tenant, not both."
unset ARM_TENANT_ID ARM_SUBSCRIPTION_ID ARM_CLIENT_ID

tofu init -backend-config=../backend.hcl -backend-config="key=prod/network.tfstate"
for k in resource_group_name location vnet_id private_endpoint_subnet_id; do
  export TF_VAR_$k="$(tofu output -raw $k)"
done

cd ../data
tofu init -backend-config=../backend.hcl -backend-config="key=prod/data.tfstate"
tofu destroy

cd ../network
tofu destroy
```

Skip whichever root you never approved. The `key` must be the one in the
matching custom resource: pointing a root at another root's state would make
the destroy target the wrong resources.

Finally, from `chapter09/identity`, `tofu destroy` removes the managed
identity, the federation and the state storage account. Do this last and not
before: the storage account holds the production state the step above depends
on, and the identity is the one every runner used for its destroy.

Then check the portal rather than trusting the exit codes. Confirm that the
three environment resource groups are gone, that no private endpoints remain,
and that the state storage account has been deleted rather than emptied.
Private endpoints in particular survive a partial teardown and keep billing.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `no matches for kind "Terraform"` | The controller is not installed | `kubectl -n flux-system get kustomization tofu-controller` — the infrastructure Kustomization `dependsOn` it |
| Runner pod `CrashLoopBackOff`, log mentions gRPC | Runner image tag does not match the controller version | Rebuild from `ghcr.io/flux-iac/tf-runner:<controller-version>-base` |
| `tofu: not found` in the runner log | `runner.image` points at a `-base` tag, which has no binary | Use the stock tag, or build from `runner/` and point at your own image |
| Runner pods never appear in `infra-dev` | `allowedNamespaces` nested under `runner` instead of `runner.serviceAccount` | Helm ignores the misplaced key silently; fix the nesting and reconcile the HelmRelease |
| `AADSTS70021: No matching federated identity record` | Namespace or service account name in the federation subject is wrong, **or** the management cluster (Chapter 8) was rebuilt since `identity/` was last applied, so its OIDC issuer URL no longer matches | Subject must be `system:serviceaccount:<ns>:tf-runner`; if the cluster was rebuilt, re-apply `identity/` with the current `TF_VAR_oidc_issuer_url` — see the Prerequisites callout |
| GitHub Actions `AADSTS700213` on the pull request gate | the `plan` job is not running in the `iac-plan` environment (the credential trusts `…:environment:iac-plan` only), **or** the fork has immutable OIDC subject claims enabled, so GitHub's subject prefix is `repo:owner@ownerId/repo@repoId`, not `repo:owner/repo` | keep `environment: iac-plan` on the job and match `TF_VAR_ci_environment`; check `gh api /repos/<owner>/<repo>/actions/oidc/customization/sub --jq .sub_claim_prefix` and set `TF_VAR_github_oidc_subject_prefix` before re-applying `identity/` |
| `plan` job waits forever | the `iac-plan` environment requires a reviewer | approve the deployment in the pull request's checks view; that approval is the gate |
| Authentication fails with an empty client id | `azure-environment` ConfigMap built from unset variables | Re-run the exports at the end of step 1, then recreate the ConfigMap |
| `dev-data` stuck in `Unknown` | `dev-network` has not written its outputs Secret yet | `kubectl -n flux-system describe tf/dev-network` |
| Variables from the outputs Secret are empty | Output names and variable names differ | Match them, or map with `varsFrom[].varsKeys` |
| Application is healthy but cannot reach storage | Private DNS zone missing or not linked to the vnet | `modules/data` creates `privatelink.blob.core.windows.net` and links it; check the link exists for the right vnet |
| State locked after a runner was evicted | Lease left behind | `tfctl force-unlock`; do not set `forceUnlock: auto` in production |
| Terraform object never leaves `Reconciliation in progress` | Runner pod cannot reach port 30000 | Check NetworkPolicy; `cluster.networkPolicy` in the FluxInstance |
| `prod-network` keeps asking for a new approval after every approval commit | The object plans from the same GitRepository its manifest lives in, so the approval commit changes the plan id ([#1878](https://github.com/flux-iac/tofu-controller/issues/1878)) | `sourceRef` must be `infra-modules`, pinned to a tag; copy the id exactly, it is compared as a whole string |
| `infra-modules` not Ready: `couldn't find remote ref` | The tag does not exist in the repository `spec.url` points at | `git tag infra-v1.0.0 && git push origin infra-v1.0.0` in your fork |
| HelmRelease install fails: `namespaces "infra-dev" not found` | A namespace in `allowedNamespaces` does not exist yet | `flux/namespaces.yaml` must be listed before `tofu-controller.yaml` in `flux/kustomization.yaml` |
| `tofu init` in CI or at the terminal: `AuthorizationPermissionMismatch` on the state blob | Shared keys are disabled, so reading state needs a data-plane role | The bootstrap grants `Storage Blob Data Contributor` to whoever applied it and `Storage Blob Data Reader` to the CI identity; role assignments can take a few minutes to apply |
| `tofu init` at the terminal: `AzureCLICredential: ERROR: Please specify only one of subscription and tenant, not both` | `ARM_TENANT_ID` and `ARM_SUBSCRIPTION_ID` are still exported from step 1, conflicting with the Azure CLI fallback a local (non-OIDC) `backend.hcl` init uses | `unset ARM_TENANT_ID ARM_SUBSCRIPTION_ID ARM_CLIENT_ID` in that shell, then retry |
| Conftest reports `will be destroyed` but the check stays green | `warn` rules do not fail Conftest by default | The workflow passes `--fail-on-warn` for staging and prod |
| `infrastructure` Kustomization never becomes Ready | Something in `chapter09/terraform` cannot reach Ready | Health checks name `dev-network` and `dev-data` only. Do not add `wait: true`: it would health-check the production objects, which hold at plan by design. Objects that need another cloud belong in `examples/` |

---

## Versions this chapter was written against

| Component | Version | Checked |
|---|---|---|
| OpenTofu | 1.12.9 | October 2026 |
| Terraform | 1.16.x (BUSL 1.1) | September 2026 |
| Flux | 2.7.x (see `flux/flux-instance.yaml`) | September 2026 |
| Flux CLI | 2.9 or later (plugin system) | September 2026 |
| Flux Operator | `fluxcd.controlplane.io/v1` | September 2026 |
| Tofu Controller | v0.16.5 | September 2026 |
| Terraform CRD | `infra.contrib.fluxcd.io/v1alpha2` | September 2026 |
| azurerm provider | ~> 5.0 | September 2026 |
| aws provider | ~> 6.0 | September 2026 |
| random provider | ~> 3.9 | September 2026 |
