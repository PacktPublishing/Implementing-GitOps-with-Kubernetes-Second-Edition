# State and plan encryption with Azure Key Vault

The chapter's listing, as a file you can drop into a root. It is **not** wired
into the walkthrough, because enabling encryption changes who can read state
and gets one thing badly wrong if you skip a step: an encrypted state cannot be
read without the key, ever.

Requires **OpenTofu 1.11 or later** (the `azure_vault` key provider arrived in
1.11). Terraform has no equivalent and rejects the `encryption` block.

## 1. Create the key

```bash
cd chapter09/identity
tofu apply \
  -var enable_state_encryption=true \
  -var state_key_vault_name=gitopskv<yourinitials>

tofu output -raw state_key_vault_uri
tofu output -raw state_key_name
```

This creates a Key Vault with RBAC authorization and purge protection, an RSA
key `tfstate-prod`, and grants **Key Vault Crypto Service Encryption User**
(keys/read, wrap, unwrap) on that key to the runner identity, and to the CI
identity if you created one. OpenTofu wraps a fresh data key per file with RSA-OAEP-256,
which is why wrap and unwrap are the only operations needed.

## 2. Add the configuration

Copy `encryption.tf` into the root you want to protect, for example
`iac/azure/prod/network/`, and set the default of `key_vault_uri` to the
URI from step 1. Commit, tag, and advance `ref.tag` in
`terraform/infra-modules-source.yaml` so production picks it up.

## 3. Migrate, then remove the fallback

The first apply reads the existing plain-text state through the
`unencrypted` fallback and writes it back encrypted. Once
`kubectl -n flux-system get tf/prod-network` shows the apply succeeded:

1. Remove `method "unencrypted" "migrate" {}` and both `fallback` blocks.
2. Optionally add `enforced = true` to `state` and `plan`.
3. Commit and advance the tag again.

Leaving the fallback in place means an attacker who can write the state blob
can replace it with a plain-text one and OpenTofu will read it.

## What changes for everyone else

- **CI.** The pull request gate plans production against its real state, so it
  now needs to unwrap the key, and can therefore read every value in the
  production state. The bootstrap grants that when `github_repository` is set.
  If that trade is wrong for you, drop production from the CI plan.
- **Local cleanup.** A `tofu destroy` from your terminal needs the same
  permission for your own user. With Azure CLI authentication, do not also
  export `ARM_SUBSCRIPTION_ID` in that shell: OpenTofu 1.11 and 1.12 fail with
  *"Please specify only one of subscription and tenant, not both"*
  ([opentofu/opentofu#3520](https://github.com/opentofu/opentofu/issues/3520)).
- **Teardown.** Destroy the roots before the bootstrap. Purge protection keeps
  the vault soft-deleted for seven days after `tofu destroy`, and its name
  cannot be reused until then.

## On AWS

Replace the key provider with `aws_kms`, give it a `kms_key_id`, a `region` and
`key_spec = "AES_256"`, and allow the IRSA role `kms:GenerateDataKey` and
`kms:Decrypt` on that key.
