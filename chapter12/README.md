# Chapter 12. Secrets, Identity, and Policy in GitOps

Companion code for *Implementing GitOps with Kubernetes, 2nd Edition*.

The chapter explains the reasoning, the trade-offs and the design decisions.
**This README holds the full step-by-step walkthrough**, for AKS and EKS, so
that it can be followed at a terminal and corrected as the tools move.

---

## What changed since the first edition

The first edition (`chapter13` in this repository, kept unchanged for
reference) treated security as a set of add-ons. This edition treats secrets,
identity and policy as one system that is delivered through GitOps itself.

| | First edition | Second edition |
|---|---|---|
| Argo CD | 2.10 | 3.x (RBAC changes from 3.0 applied) |
| Kyverno | 1.11, `kyverno.io/v1 ClusterPolicy` | 1.19, `policies.kyverno.io/v1 ValidatingPolicy` (CEL) |
| OPA | mentioned only | Gatekeeper 3.23 ConstraintTemplate example |
| Native admission | not covered | `ValidatingAdmissionPolicy` (GA in Kubernetes 1.30) |
| ESO | 0.9.13, `external-secrets.io/v1beta1` | 2.13.0, `external-secrets.io/v1` |
| Sealed Secrets | chart 2.15.0 | chart 2.20.0 (controller v0.40.0) |
| SOPS | not covered | SOPS + age / Azure Key Vault / AWS KMS with Flux |
| ESO authentication | client ID + secret | Entra Workload ID (AKS), EKS Pod Identity + session tags (EKS) |
| Argo CD hub | Cockpit cluster, local admin | Self-managed Argo CD 3.5 on the Chapter 8 AKS cluster, Entra SSO with Workload ID (no client secret) |
| Argo CD cluster credentials | never-expiring bearer token | AKS hub to EKS through AWS web-identity federation (no AWS key), `argocd-k8s-auth azure` for further AKS spokes |
| Sync identity | Argo CD controller (cluster-admin) | Sync impersonation: every project syncs as a named service account |
| Pull-secret fan-out | ESO + Kyverno generate | ESO `ClusterExternalSecret` |
| ApplicationSets | legacy templating, `repoURL … .gitt` | `goTemplate: true`, fixed URLs, dedicated AppProject |
| Scanning | KubeClarity (archived Oct 2024) | out of scope; see chapter text |

---

## Layout

```
chapter12/
├── hub/
│   ├── iac/                Entra SSO app (Workload ID), AWS OIDC provider + role, EKS access entry
│   ├── argocd/             Argo CD 3.5.6 on AKS (Kustomize), cluster declarations, self-management
│   └── spoke-bootstrap/    Sync identity and hub-reader RBAC for every managed cluster
├── applicationsets/        Platform security baseline delivered to every cluster
├── secrets/
│   ├── sealed-secrets/     Encrypt-in-Git, cluster-bound key
│   ├── sops/               Encrypt-in-Git, KMS- or age-wrapped key, Flux decryption
│   └── external-secrets/   Reference-in-Git: operator, stores per cloud, portable ExternalSecret
├── identity/
│   ├── argocd/             Tenant AppProject, tenant deployer, extra AKS spoke example
│   └── flux/               Multi-tenancy lockdown and a tenant definition
├── policy/
│   ├── kyverno/            Engine chart, CEL policies, overlays, exceptions, CLI tests
│   ├── gatekeeper/         The same rule written for OPA Gatekeeper
│   └── admission/          Kubernetes-native ValidatingAdmissionPolicy
├── iac/
│   ├── azure/              Key Vault, managed identity, federated credential
│   └── aws/                Pod Identity association, ABAC tenant role
└── ci/.github/             Offline PR gates and CODEOWNERS (copy to repo root)
```

---

## Prerequisites

* The AKS and/or EKS clusters from **Chapter 8** (`chapter08/iac`). This chapter
  adds to them; it does not create new clusters.
* Rights to create an Entra ID application registration in your tenant and an
  IAM OIDC provider and role in your AWS account.
* Nothing else: step 0 installs a small, self-managed Argo CD hub on the
  Chapter 8 AKS cluster. It is separate from the managed EKS capability for
  Argo CD that Chapter 8 uses for the weather-app; the two coexist.
* Before a first run, follow [`TESTING.md`](TESTING.md): the code has not yet been run against live clusters.
* CLIs: `kubectl`, `helm` 3.x or 4.x, `argocd` 3.x, `flux` 2.9+, `kubeseal`
  0.40+, `sops` 3.13+, `age`, `kyverno` 1.19, Terraform 1.9+ or OpenTofu,
  `az` and/or `aws`.

> **Cost warning.** Key Vault and Secrets Manager charge per secret and per
> 10,000 operations. Clean up at the end (see below).

---

## Walkthrough

### 0. The Argo CD hub on AKS

Chapter 8 runs Flux on AKS and the managed EKS capability for Argo CD on EKS.
Neither can carry this chapter's SSO, RBAC and impersonation settings, and the
EKS capability cannot target AKS, so Chapter 12 adds a self-managed Argo CD
3.5.6 hub to the AKS cluster. It manages itself (in-cluster, labelled
`environment=development`) and the EKS cluster (`environment=production`).

```
Entra ID ──(SSO, Workload ID, no client secret)──► argocd-server
AKS issuer ──(projected token, aud sts.amazonaws.com)──► AWS STS ──► argocd-hub role
argocd-hub role ──(EKS access entry, group argocd-hub)──► read + impersonate on EKS
every sync ──(impersonation)──► argocd-impersonation:platform-installer / team-a-deployer
```

**0.1 Identities** (Entra app + federated credential, IAM OIDC provider + role,
EKS access entry):

```bash
cd chapter12/hub/iac
tofu init && tofu apply
TENANT_ID=$(tofu output -raw tenant_id)
CLIENT_ID=$(tofu output -raw argocd_client_id)
ROLE_ARN=$(tofu output -raw argocd_hub_role_arn)
cd ../argocd
grep -rl REPLACE_WITH_ install clusters | xargs sed -i.bak \
  -e "s#REPLACE_WITH_TENANT_ID#$TENANT_ID#" \
  -e "s#REPLACE_WITH_ARGOCD_CLIENT_ID#$CLIENT_ID#" \
  -e "s#REPLACE_WITH_ARGOCD_HUB_ROLE_ARN#$ROLE_ARN#"
read -r EKS_ENDPOINT EKS_CA < <(aws eks describe-cluster --name eks-gitops-ch08 \
  --query 'cluster.[endpoint,certificateAuthority.data]' --output text)
sed -i.bak -e "s#REPLACE_WITH_EKS_ENDPOINT#$EKS_ENDPOINT#" \
  -e "s#REPLACE_WITH_BASE64_CA#$EKS_CA#" clusters/eks-gitops-ch08.yaml
rm -f install/*.bak clusters/*.bak
```

Replace the two `REPLACE_WITH_*_GROUP_ID` values in
`install/argocd-rbac-cm.yaml` with the object IDs of your Entra ID platform-admin
and auditor groups, and assign those groups to the `argocd-gitops-ch12`
enterprise application. Commit and push these values to your fork: the hub
reconciles itself from Git, so local edits that are not pushed are reverted.

**0.2 Register EKS as a spoke** (once, with your own EKS admin credentials):

```bash
kubectl --context eks-gitops-ch08 apply -k chapter12/hub/spoke-bootstrap
```

**0.3 Bootstrap the hub** (once, with your Entra ID credentials on AKS):

```bash
kubectl --context aks-gitops-ch08 apply --server-side --force-conflicts \
  -k chapter12/hub/argocd
kubectl --context aks-gitops-ch08 -n argocd rollout status statefulset/argocd-application-controller
kubectl --context aks-gitops-ch08 -n argocd delete secret argocd-initial-admin-secret --ignore-not-found
```

From now on the `argocd-hub` Application reconciles `chapter12/hub/argocd`,
including the ApplicationSets in `applicationsets/`. Reach the UI with:

```bash
kubectl --context aks-gitops-ch08 -n argocd port-forward svc/argocd-server 8080:443
argocd login localhost:8080 --sso --grpc-web
argocd cluster list     # aks-gitops-ch08 (in-cluster) and eks-gitops-ch08: Successful
```

> The hub's own identity on EKS can only read and impersonate
> (`spoke-bootstrap/hub-reader.yaml`). Every write is made as the service
> account named in the AppProject's `destinationServiceAccounts`.

### 1. Cloud identity for ESO

**Azure**

```bash
cd chapter12/iac/azure
tofu init && tofu apply -var subscription_id=$ARM_SUBSCRIPTION_ID -var tenant_id=$ARM_TENANT_ID
CLIENT_ID=$(tofu output -raw eso_reader_client_id)

az keyvault secret set --vault-name kv-gitops-ch12 \
  --name weather-app-db --value "$(openssl rand -base64 24)"

sed -i "s/REPLACE_WITH_CLIENT_ID/$CLIENT_ID/" \
  ../../secrets/external-secrets/stores/azure/serviceaccount.yaml
```

**AWS**

```bash
cd chapter12/iac/aws
tofu init && tofu apply
ROLE_ARN=$(tofu output -raw tenant_role_arn)

aws secretsmanager create-secret --name weather-app-db \
  --secret-string "$(openssl rand -base64 24)" \
  --tags Key=namespace,Value=weather-app

sed -i "s#arn:aws:iam::ACCOUNT_ID:role/eks-gitops-ch08-weather-app-secrets#$ROLE_ARN#" \
  ../../secrets/external-secrets/stores/aws/secretstore.yaml
```

### 2. The platform baseline

Already delivered: the hub's own kustomization includes `applicationsets/`.

```bash
argocd app list -p platform-security
```

Expected: `external-secrets-aks-gitops-ch08`, `external-secrets-eks-gitops-ch08`,
`kyverno-aks-gitops-ch08` (development overlay, Audit) and
`kyverno-eks-gitops-ch08` (production overlay, Deny), all `Synced` and `Healthy`.

### 3. Store and ExternalSecret

```bash
# AKS
kubectl apply -k chapter12/secrets/external-secrets/stores/azure
# EKS
kubectl apply -k chapter12/secrets/external-secrets/stores/aws

# Both: the same file
kubectl apply -k chapter12/secrets/external-secrets/app
kubectl -n weather-app get externalsecret weather-db
```

Expected: `STATUS SecretSynced`, `READY True`. In production these
directories are reconciled by Argo CD or Flux, not applied by hand.

### 4. Encrypt-in-Git alternatives

* **Sealed Secrets**: see `secrets/sealed-secrets/README.md`.
* **SOPS with Flux**: create an age key, store the private key as the
  `sops-age` Secret in `flux-system`, put the public key in
  `secrets/sops/.sops.yaml`, encrypt, commit, and apply
  `secrets/sops/flux-kustomization.yaml`.

```bash
age-keygen -o age.agekey
kubectl -n flux-system create secret generic sops-age --from-file=age.agekey
shred -u age.agekey     # keep a copy only in the break-glass vault
```

### 5. Argo CD identity

SSO, RBAC, impersonation and the cluster credentials were set up in step 0.
Check what they allow:

```bash
argocd account get-user-info            # your Entra ID groups
argocd admin settings rbac can role:auditor get applications '*/*' \
  --policy-file chapter12/hub/argocd/install/argocd-rbac-cm.yaml   # Yes
argocd admin settings rbac can role:auditor sync applications '*/*' \
  --policy-file chapter12/hub/argocd/install/argocd-rbac-cm.yaml   # No
kubectl --context eks-gitops-ch08 auth can-i create deployments -A \
  --as=argocd-hub --as-group=argocd-hub                             # no
```

Tenant onboarding: apply `identity/argocd/appproject-team-a.yaml` to the hub
and `identity/argocd/team-a-deployer.yaml` to each destination cluster.
Sync impersonation was introduced in Argo CD 2.13 and is a beta feature since
3.5, where it is enforced: a project without a matching
`destinationServiceAccounts` entry cannot sync. During a migration,
`application.sync.impersonation.enforced: "false"` falls back to the
controller's account.

For further AKS spokes, see `identity/argocd/cluster-secret-aks-spoke.yaml`.

### 6. Flux tenancy

Add `identity/flux/lockdown/kustomization.yaml` to your `flux-system`
bootstrap directory, then apply `identity/flux/tenant-team-a.yaml`.

```bash
flux get kustomizations -n team-a
kubectl auth can-i create clusterrolebinding \
  --as=system:serviceaccount:team-a:team-a-reconciler     # expected: no
```

### 7. Policy: audit first, then deny

```bash
# Development (Audit): the pod is admitted, a PolicyReport records the failure.
kubectl run nginx --image nginx:latest -n weather-app
kubectl get policyreport -n weather-app -o wide

# Production (Deny): the same request is rejected at admission.
kubectl --context aks-prod run nginx --image nginx:latest -n weather-app
# Error from server: admission webhook "...kyverno.svc..." denied the request:
#   disallow-latest-tag: Using a mutable image tag such as 'latest' is not allowed.
```

Migration from the first-edition policy:

```bash
kyverno apply chapter12/policy/kyverno/legacy/disallow-latest-tag.clusterpolicy.yaml \
  --resource chapter12/policy/kyverno/tests/resources.yaml --warnings-as-errors
# fails: ClusterPolicy is deprecated
kyverno test chapter12/policy/kyverno/tests
```

Gatekeeper alternative (do not install alongside the AKS Azure Policy add-on):

```bash
kubectl apply -f chapter12/policy/gatekeeper/templates/
kubectl apply -f chapter12/policy/gatekeeper/constraints/
kubectl get k8sdisallowedtags disallow-latest -o yaml | yq .status.violations
```

Native admission policy (no engine required):

```bash
kubectl apply -f chapter12/policy/admission/deny-privileged.yaml
```

### 8. Pull-request gates

Copy `ci/.github/workflows/ch12-policy-gates.yml` and `ci/.github/CODEOWNERS`
to `.github/` at the repository root. The workflow needs no cloud or cluster
credentials: it scans for secrets, rejects unencrypted `Secret` manifests and
runs the Kyverno CLI against the rendered Chapter 8 application.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `SecretSyncedError … AADSTS700213` | Federated credential subject does not match | Subject must be `system:serviceaccount:weather-app:eso-reader` exactly |
| `unable to create session: an IAM role must be associated with service account` | `serviceAccountRef` used with EKS Pod Identity | Remove `auth.jwt`; use `role` + `sessionTagsPolicy` |
| `AccessDenied` from Secrets Manager | Secret not tagged `namespace=weather-app` | Add the tag; ABAC compares it with the session tag |
| Kyverno policy not applied by Argo CD | CRDs not yet present | `SkipDryRunOnMissingResource=true` is set; resync once |
| `Warning: kyverno.io/v1 ClusterPolicy is deprecated` | Legacy policy in a synced path | Migrate to `ValidatingPolicy` |
| Argo CD UI shows no logs | Argo CD 3.x enforces `logs, get` | Add the permission to the role |
| Sync fails: `no matching service account found for destination` | Impersonation is enforced since 3.5 | Add `destinationServiceAccounts` to the project |
| `eks-gitops-ch08` connection fails: `InvalidIdentityToken` | IAM OIDC provider URL differs from the token `iss` (often the trailing slash) | Recreate the provider with `oidc_issuer_url` exactly as AKS reports it |
| `eks-gitops-ch08` connection fails: `Unauthorized` | Access entry or `hub-reader` binding missing | Check `aws eks list-access-entries` and step 0.2 |
| SSO login: `AADSTS70021` | Federated credential subject does not match | Subject must be `system:serviceaccount:argocd:argocd-server` |
| Flux `Kustomization` fails with `serviceaccounts "default" is forbidden` | Lockdown active, tenant did not set `serviceAccountName` | Set it explicitly |

## Cleaning up

```bash
kubectl --context aks-gitops-ch08 -n argocd delete application argocd-hub --cascade=orphan
kubectl --context aks-gitops-ch08 delete -k chapter12/hub/argocd
kubectl --context eks-gitops-ch08 delete -k chapter12/hub/spoke-bootstrap
cd chapter12/hub/iac && tofu destroy && cd ../..
cd iac/azure && tofu destroy
cd ../aws && tofu destroy
aws secretsmanager delete-secret --secret-id weather-app-db --recovery-window-in-days 7
```

Key Vault purge protection keeps the vault for the retention period; that is
intended.
