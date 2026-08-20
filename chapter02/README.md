# kubara local evaluation

> **Warning:** This is only a fallback in case the upstream kubara project
> changes. It allows you to build kubara with either a mirrored catalog or a
> local offline catalog.

This directory contains a copy of the kubara source code and the catalogs used
in this chapter. You can build the CLI with its standard remote catalog
defaults or use the checked-in catalogs as local defaults.

Building requires Go and GNU Make. The first build may download the Go
toolchain specified in `kubara/src/go.mod` and the required Go modules.

## Option 1: standard build

Build kubara for the current platform:

```bash
make build
```

Build kubara for Linux, macOS, and Windows on amd64 and arm64:

```bash
make build-all
```

When no build option is specified, kubara retains the existing catalog
defaults:

```text
oci://ghcr.io/la-cc/catalogs/bootstrap:2.0.0
oci://ghcr.io/la-cc/catalogs/general:2.0.0
```

## Option 2: build with local catalogs

Build for the current platform using the checked-in catalog paths as defaults:

```bash
make build OFFLINE=1
```

Or cross-build all supported binaries:

```bash
make build-all OFFLINE=1
```

This compiles the following default references into kubara:

```text
./catalogs/bootstrap
./catalogs/general
```

The paths are resolved relative to kubara's working directory. Run the offline
binary from `chapter02` or pass `--work-dir` explicitly.

You can override the paths during the build if required:

```bash
make build OFFLINE=1 \
  OFFLINE_BOOTSTRAP_CATALOG=/opt/kubara/catalogs/bootstrap \
  OFFLINE_GENERAL_CATALOG=/opt/kubara/catalogs/general
```

## Option 3: build kubara and change the configuration defaults

Build kubara as described in Option 1, or use kubara v0.14.0 (tested), and then
modify the generated `config.yaml`.

Build kubara for the current platform:

```bash
make build
```

Build kubara for Linux, macOS, and Windows on amd64 and arm64:

```bash
make build-all
```

First, generate `config.yaml`:

```bash
kubara init --local --renovate=false
```

Then update the catalog path as needed:

```yaml
version: v1alpha4
clusters:
  - name: test-cluster
    ...
    catalogs:
      - ./catalogs/general
```

## Run the local evaluation

The binary for the current platform is written to `kubara/src/kubara`. Add it
to your `PATH`, then follow the standard kubara local-evaluation tutorial:

```bash
export PATH="$PWD/kubara/src:$PATH"

kubara init --prep --local
# Edit .env.
kubara init --local --renovate=false
kubara bootstrap test-cluster --local
```

For the bootstrap, start `sudo cloud-provider-kind` in a second terminal when
kubara asks for it.

The cross-platform binaries are written to `kubara/src/` with their operating
system and architecture in the filename.
