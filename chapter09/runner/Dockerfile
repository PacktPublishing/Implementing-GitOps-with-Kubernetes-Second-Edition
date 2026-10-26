# -----------------------------------------------------------------------------
# Custom Tofu Controller runner image
#
# You usually do not need this file.
#
# The published tf-runner image already contains OpenTofu: the project's own
# runner.Dockerfile copies the tofu binary out of
# ghcr.io/opentofu/opentofu:<version>-minimal, which for the v0.16.5 line is
# OpenTofu 1.12.1. Build your own only when you need a different OpenTofu
# version, Terraform rather than OpenTofu, or extra tooling such as a private
# certificate bundle.
#
# Pin both versions: the base tag must match the controller version exactly,
# because the controller and the runner speak a versioned gRPC API.
#
# Build:
#   export TF_CONTROLLER_VERSION=v0.16.5
#   export TOFU_VERSION=1.12.9
#   docker build \
#     --build-arg BASE_IMAGE=ghcr.io/flux-iac/tf-runner:${TF_CONTROLLER_VERSION}-base \
#     --build-arg TOFU_VERSION=${TOFU_VERSION} \
#     -t ghcr.io/<your-org>/tofu-runner:${TF_CONTROLLER_VERSION} .
# -----------------------------------------------------------------------------

ARG BASE_IMAGE
ARG TOFU_VERSION=1.12.9

FROM ghcr.io/opentofu/opentofu:${TOFU_VERSION}-minimal AS tofu

FROM $BASE_IMAGE

COPY --from=tofu /usr/local/bin/tofu /usr/local/bin/tofu

# The runner never needs a cloud CLI. The first edition installed the Azure CLI
# into this image so that the provider could pick up an `az login` session;
# with workload identity federation the provider reads a projected token file
# instead, and the image stays small and free of long-lived credentials.

USER 65532:65532
