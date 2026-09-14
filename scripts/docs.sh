#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# mkdocsgo-example - run the documentation toolbox against this repository
#
# Every other script in scripts/ is a one-line call to this one. It does a
# single thing: mount this repository into the mkdocs-build-toolbox image and
# run the `docs` command inside it.
#
# That image carries the documentation toolchain - MkDocs and its plugins, and
# the shared build logic - so this repository needs no Python of its own. It
# deliberately does not carry the machine's own tooling: the container engine
# that runs it, and the `cf` client that pushes what it produced.
#
# Deployment is therefore not here. The toolbox assembles an artefact and
# stops; pushing it is scripts/deploy-cf.sh, run on the host with the
# operator's own session.
#
# The image version is pinned in project.conf, like any other dependency.
# Upgrading the toolchain is one line there and a commit.
#
# Usage:
#   scripts/docs.sh test
#   scripts/docs.sh package-cf --clean
#
# Environment:
#   DOCKER         force a container CLI (default: docker, then podman)
#   TOOLBOX_IMAGE  override the image from project.conf, for a one-off run
# ---------------------------------------------------------------------------

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

die() { printf '\033[31mERROR\033[0m %s\n' "$*" >&2; exit 1; }

# project.conf is parsed, never sourced: values are literal and nothing in the
# file can execute code. Only the one key this script needs is read here; the
# rest is the image's business.
if [ -z "${TOOLBOX_IMAGE:-}" ]; then
  TOOLBOX_IMAGE="$(sed -n 's/^TOOLBOX_IMAGE=//p' "$REPO_ROOT/project.conf" | head -1)"
fi
[ -n "$TOOLBOX_IMAGE" ] || die "TOOLBOX_IMAGE is not set in project.conf"

if [ -n "${DOCKER:-}" ]; then
  command -v "$DOCKER" >/dev/null 2>&1 || die "DOCKER is set to '$DOCKER' but it is not on PATH"
elif command -v docker >/dev/null 2>&1; then
  DOCKER=docker
elif command -v podman >/dev/null 2>&1; then
  DOCKER=podman
else
  die "neither docker nor podman found on PATH
     One of them is all this repository needs - the toolchain lives in
     $TOOLBOX_IMAGE. Install one and try again."
fi

args=(--rm -i -t
  --volume "$REPO_ROOT:/work"
  --workdir /work
  --env "TERM=${TERM:-dumb}")

# `docker` here may be a podman shim, and the two need opposite --user
# handling, so ask the binary what it is rather than trusting its name.
# Rootless podman already maps the container's root to the invoking user;
# --user there would map into the subuid range and make /work unwritable.
# Docker needs it, or everything the build writes is owned by root.
if ! "$DOCKER" --version 2>/dev/null | grep -qi podman; then
  args+=(--user "$(id -u):$(id -g)")
fi

case "${1:-}" in
  serve)
    # mkdocs binds 0.0.0.0 inside the container; this is the only way the host
    # reaches it.
    port="$(sed -n 's/^LOCAL_PORT=//p' "$REPO_ROOT/project.conf" | head -1)"
    for arg in "$@"; do
      case "$arg" in ''|*[!0-9]*) ;; *) port="$arg" ;; esac
    done
    args+=(--publish "127.0.0.1:${port:-8000}:${port:-8000}")
    ;;
esac

exec "$DOCKER" run "${args[@]}" "$TOOLBOX_IMAGE" "$@"
