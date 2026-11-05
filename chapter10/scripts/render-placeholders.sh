#!/usr/bin/env bash
# Fill the REPLACE_WITH_* placeholders in chapter10/ from the OpenTofu outputs
# and a few values only you know. Run it in your fork, review the diff, and
# commit it: from then on, Git is the only place these values are set.
#
#   export BASE_DOMAIN=weather.example.org     # DNS zone you control
#   export ACME_EMAIL=you@example.org          # Let's Encrypt account e-mail
#   export TEAM_GROUP_OBJECT_ID=<entra-group-object-id>
#   export GITHUB_REPO_URL=https://github.com/<you>/Implementing-GitOps-with-Kubernetes-Second-Edition.git
#   ./chapter10/scripts/render-placeholders.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
: "${BASE_DOMAIN:?}" "${ACME_EMAIL:?}" "${TEAM_GROUP_OBJECT_ID:?}" "${GITHUB_REPO_URL:?}"

out() { tofu -chdir="$HERE/iac/azure" output -raw "$1"; }
cluster() { tofu -chdir="$HERE/iac/azure" output -json clusters | jq -r ".${1}.${2}"; }
weather() { tofu -chdir="$HERE/iac/azure" output -json weather_client_ids | jq -r ".${1}"; }

declare -A values=(
  [REPLACE_WITH_TENANT_ID]="$(out tenant_id)"
  [REPLACE_WITH_ARGOCD_HUB_CLIENT_ID]="$(out argocd_hub_client_id)"
  [REPLACE_WITH_KARGO_CLIENT_ID]="$(out kargo_client_id)"
  [REPLACE_WITH_KARGO_GIT_CLIENT_ID]="$(out kargo_git_client_id)"
  [REPLACE_WITH_KEY_VAULT_URI]="$(out key_vault_uri)"
  [REPLACE_WITH_ACR_LOGIN_SERVER]="$(out acr_login_server)"
  [REPLACE_WITH_NONPROD_ENDPOINT]="$(cluster nonprod endpoint)"
  [REPLACE_WITH_NONPROD_CA_DATA]="$(cluster nonprod ca_data)"
  [REPLACE_WITH_PROD_ENDPOINT]="$(cluster prod endpoint)"
  [REPLACE_WITH_PROD_CA_DATA]="$(cluster prod ca_data)"
  [REPLACE_WITH_WEATHER_DEV_CLIENT_ID]="$(weather dev)"
  [REPLACE_WITH_WEATHER_STAGING_CLIENT_ID]="$(weather staging)"
  [REPLACE_WITH_WEATHER_PROD_CLIENT_ID]="$(weather prod)"
  [REPLACE_WITH_BASE_DOMAIN]="$BASE_DOMAIN"
  [REPLACE_WITH_ACME_EMAIL]="$ACME_EMAIL"
  [REPLACE_WITH_TEAM_GROUP_OBJECT_ID]="$TEAM_GROUP_OBJECT_ID"
)

files=$(grep -rl --exclude-dir=first_edition --exclude-dir=scripts --exclude-dir=iac \
  -e REPLACE_WITH_ -e 'PacktPublishing/Implementing-GitOps-with-Kubernetes-Second-Edition.git' "$HERE")
for f in $files; do
  for key in "${!values[@]}"; do
    sed -i.bak "s#${key}#${values[$key]}#g" "$f"
  done
  sed -i.bak "s#https://github.com/PacktPublishing/Implementing-GitOps-with-Kubernetes-Second-Edition.git#${GITHUB_REPO_URL}#g" "$f"
  rm -f "$f.bak"
done

echo "Remaining placeholders (EKS delta and local loop are expected):"
grep -rn --exclude-dir=first_edition --exclude-dir=scripts REPLACE_WITH_ "$HERE" || true
