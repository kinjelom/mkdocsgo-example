# How to depend on mkdocsgo

A documentation repository needs the server to exist somewhere. This one
depends on a **released version**, never on a source tree, and writes that
version in exactly one place: `MKDOCSGO_VERSION` in `project.conf`.

The release comes in two forms, and both are the same decision:

- the **release binary**, pinned by version and verified by checksum, for
  local runs and for the Cloud Foundry binary buildpack;
- the **release image** as a build stage, `COPY --from=ghcr.io/kinjelom/mkdocsgo:0.3.0`,
  for the container image.

| | Release binary | Release image |
|---|---|---|
| What you depend on | a versioned artefact | a versioned artefact |
| Needs a Go toolchain | no | no |
| Integrity check | **SHA-256, published separately** | image digest |
| Time to first run | a ~4 MB download | a docker pull |
| Reproducible | yes, byte for byte | yes, by digest |
| Upgrade is | one line in `project.conf` | one line in `project.conf` |
| Air-gapped | mirror one file | mirror one image |

## Why the binary and the image are both "the release"

They are not two dependencies. Packaging and the `Dockerfile` both read
`MKDOCSGO_VERSION`, so the version you run locally and the version in the image
cannot disagree:

```ini title="project.conf"
MKDOCSGO_VERSION=0.3.0
MKDOCSGO_REPO=kinjelom/mkdocsgo
MKDOCSGO_IMAGE=ghcr.io/kinjelom/mkdocsgo
```

```dockerfile title="Dockerfile (stage 2)"
FROM ${MKDOCSGO_IMAGE} AS server
...
COPY --from=server /mkdocsgo /mkdocsgo
```

`scripts/image.sh` passes `MKDOCSGO_IMAGE=${MKDOCSGO_IMAGE}:${MKDOCSGO_VERSION}`
as a build argument, so the Dockerfile never has to be edited to move a version
either.

Using the image as a build stage is better than downloading a binary inside the
Dockerfile: no `curl` in the build, no checksum logic to write twice, and the
layer is cached and shared between projects.

!!! tip "Pin the version, not `:latest`"

    `FROM ghcr.io/kinjelom/mkdocsgo:latest` in a build stage means your image
    changes when someone else cuts a release. Pin it, and let the upgrade be a
    commit you can read and revert.

## How the pin is enforced

`scripts/docs.sh package-cf` stamps the version it installed into
`dist/cf/.version`, and the checks compare that stamp with `MKDOCSGO_VERSION`
on every test run:

```
FAIL dist/cf holds mkdocsgo '0.2.0' but project.conf pins '0.3.0'
     - re-run scripts/docs.sh package-cf
```

So changing `MKDOCSGO_VERSION` is the entire upgrade procedure. There is no
separate command to remember, and a package left over from before the bump
cannot quietly outlive it.

The download is then checked before it is installed:

```
==> Installing mkdocsgo 0.2.0
==> platform   : linux/amd64
  OK sha256 f1465c65e8d28a1c0bfb0095d949033daa7b472fe443e8154448896faed877a0
```

A mismatch stops with a message and installs nothing.

## A note on vendoring the binary

Committing `mkdocsgo` into the repository would remove the download. It also
adds a 9 MB binary to every clone and every `git gc`, one per platform if
anyone develops on a Mac, and puts an executable in a repository where
reviewers do not expect one. The checksummed download achieves the same
determinism without any of that.

If your environment genuinely cannot reach GitHub, mirror the release archive
and its checksums file to wherever it *can* reach, and set
`MKDOCSGO_DOWNLOAD_BASE` in `project.conf` to that location. That is two files
per version, and the checksum check still applies - so the mirror does not have
to be trusted, only reachable.
