#!/usr/bin/env bash
# Re-register a rebuilt cluster with the hub: write its new API endpoint and CA
# into platform/hub/clusters/aks-ch10-<key>.yaml from the OpenTofu outputs.
# Commit the result through a pull request; the hub does the rest.
#
#   ./chapter10/scripts/register-cluster.sh nonprod
set -euo pipefail
KEY="${1:?usage: register-cluster.sh <nonprod|prod>}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
FILE="$HERE/platform/hub/clusters/aks-ch10-$KEY.yaml"
JSON="$(tofu -chdir="$HERE/iac/azure" output -json clusters)"
ENDPOINT="$(jq -r ".${KEY}.endpoint" <<<"$JSON")"
CA="$(jq -r ".${KEY}.ca_data" <<<"$JSON")"
sed -i.bak -E \
  -e "s#^(  server: ).*#\1${ENDPOINT}#" \
  -e "s#(\"caData\": \")[^\"]*(\")#\1${CA}\2#" "$FILE"
rm -f "$FILE.bak"
git -C "$HERE" diff --stat -- "$FILE"
