#!/usr/bin/env bash
# Local development environment for Chapter 10.
#
#   ./bootstrap.sh            kind cluster + Argo Rollouts + Argo CD
#   ./bootstrap.sh inner-loop build the image, load it into kind, apply the
#                             local overlay directly (seconds, no Git)
#   ./bootstrap.sh gitops     let the local Argo CD reconcile YOUR branch
#                             (the same path a change takes in production)
#
# Requires: docker, kind 0.30+, kubectl, git.
set -euo pipefail

ARGOCD_VERSION=v3.5.6
ROLLOUTS_VERSION=v1.10.1
HERE="$(cd "$(dirname "$0")" && pwd)"
CTX=kind-weather-local

cluster() {
  kind get clusters | grep -qx weather-local || kind create cluster --config "$HERE/kind-config.yaml"
  kubectl --context "$CTX" create namespace argo-rollouts --dry-run=client -o yaml | kubectl --context "$CTX" apply -f -
  kubectl --context "$CTX" apply -n argo-rollouts --server-side \
    -f "https://github.com/argoproj/argo-rollouts/releases/download/${ROLLOUTS_VERSION}/install.yaml"
  kubectl --context "$CTX" create namespace argocd --dry-run=client -o yaml | kubectl --context "$CTX" apply -f -
  kubectl --context "$CTX" apply -n argocd --server-side --force-conflicts \
    -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
  kubectl --context "$CTX" -n argocd rollout status deploy/argocd-server --timeout=180s
  echo "Argo CD UI: kubectl --context $CTX -n argocd port-forward svc/argocd-server 8080:443"
}

inner_loop() {
  docker build -t weather-app:local "$HERE/../src"
  kind load docker-image weather-app:local --name weather-local
  kubectl --context "$CTX" apply -k "$HERE/overlay"
  kubectl --context "$CTX" -n weather-local rollout restart deploy/weather-cache >/dev/null 2>&1 || true
  kubectl --context "$CTX" argo rollouts -n weather-local get rollout weather-app 2>/dev/null \
    || kubectl --context "$CTX" -n weather-local get pods
  echo "Try it: kubectl --context $CTX -n weather-local port-forward svc/weather-app 8081:80"
}

gitops() {
  local repo branch
  repo="$(git -C "$HERE" remote get-url origin | sed -E 's#^git@github.com:#https://github.com/#')"
  branch="$(git -C "$HERE" rev-parse --abbrev-ref HEAD)"
  sed -e "s#REPLACE_WITH_YOUR_FORK#${repo}#" -e "s#REPLACE_WITH_YOUR_BRANCH#${branch}#" \
    "$HERE/argocd-application.yaml" | kubectl --context "$CTX" apply -f -
  echo "Argo CD now reconciles ${branch} of ${repo}. Push to see changes applied."
}

case "${1:-cluster}" in
  cluster) cluster ;;
  inner-loop) inner_loop ;;
  gitops) gitops ;;
  *) echo "usage: $0 [cluster|inner-loop|gitops]"; exit 1 ;;
esac
