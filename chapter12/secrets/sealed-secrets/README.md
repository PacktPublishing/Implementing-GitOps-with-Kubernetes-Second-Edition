# Sealed Secrets

```bash
# Fetch the public certificate once; it is safe to commit.
kubeseal --controller-name sealed-secrets-controller \
         --controller-namespace sealed-secrets \
         --fetch-cert > pub-cert.pem

# Seal a secret without ever writing the plaintext to disk.
kubectl create secret generic weather-db \
  --namespace weather-app \
  --from-literal=password="$(openssl rand -base64 24)" \
  --dry-run=client -o yaml |
kubeseal --cert pub-cert.pem --format yaml > weather-db.sealedsecret.yaml
```

The default scope is `strict`: the ciphertext is bound to the name **and**
namespace. Renaming or moving the object breaks decryption by design.

Back up the sealing keys (`kubectl -n sealed-secrets get secret
-l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml`) into your
break-glass vault. Losing them means re-sealing every secret.
