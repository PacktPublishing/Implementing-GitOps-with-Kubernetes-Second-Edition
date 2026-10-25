# Examples: apply these by hand

Neither file here is reconciled by the management cluster, and that is
deliberate. `chapter09/terraform` is applied wholesale by the `infrastructure`
Kustomization, and an object that can never become Ready in that directory
would hold up the readiness signal the application layer depends on.

Apply them yourself when you want them:

```bash
kubectl apply -f chapter09/examples/aws-dev.yaml
```

| File | Why it is not reconciled |
|---|---|
| `aws-dev.yaml` | Needs IRSA on an EKS cluster. On the Azure management cluster the AWS provider has no identity to assume and the object stays unhealthy. |
| `legacy-drift-only.yaml` | Points at a configuration describing infrastructure *you* already own. There is nothing in the book repository for it to describe, so you must supply `path` yourself. |
| `state-encryption/` | Not a custom resource: an `encryption.tf` to copy into a root, plus the steps to migrate existing state. It changes who can read state, so it is opt-in. |
