# First-edition code (reference only)

Kept unchanged so that readers of the first edition can still find it.

| Folder | First edition | Second edition |
|---|---|---|
| `real-world-projects/` | Chapter 11, *Deploying Real-World Projects with GitOps on Kubernetes* (was `old_chapter11_is_now_chapter10/` in this repository) | Rewritten as Chapter 10 (`chapter10/`) |
| `terraform-flux-cd/` | Chapter 10, *GitOps for Infrastructure Automation – Terraform and Flux CD* (was `chapter10/`) | Rewritten as Chapter 9 (`chapter09/`) |

Do not use this code as a starting point: it relies on a service-principal
secret, pushes to clusters from CI, and uses retired or outdated APIs. See the
table at the top of `chapter10/README.md` for what changed and why.
