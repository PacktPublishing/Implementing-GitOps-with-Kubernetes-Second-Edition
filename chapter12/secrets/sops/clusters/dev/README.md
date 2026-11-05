Place SOPS-encrypted Secret manifests for the development cluster here, plus a
`kustomization.yaml` that lists them. Encrypt with:

```bash
kubectl create secret generic weather-db --namespace weather-app \
  --from-literal=password="$(openssl rand -base64 24)" \
  --dry-run=client -o yaml > weather-db.yaml
sops --encrypt --in-place weather-db.yaml   # rules come from ../../.sops.yaml
```

Never commit the file before `sops --encrypt` has run; the CI job
`ch12-policy-gates` rejects any `kind: Secret` without a `sops:` block.
