#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# mkdocsgo-example - deploy to Cloud Foundry
#
# Two ways to run the same documentation, and the flag chooses:
#
#   --docker     push an image reference. Cloud Foundry pulls it from the
#                registry; the push builds nothing. Needs a registry the
#                foundation can reach.
#
#   --buildpack  push a directory of files assembled by scripts/docs.sh package-cf,
#                started by the binary buildpack. Needs no registry at all.
#
# The manifests hold everything environment-specific - name, route, instances,
# quotas, health check. The one exception is the image reference, which is
# passed in as a manifest variable: the version must have exactly one home, and
# that home is extra.app_version in mkdocs.yml.
#
# That placeholder is also a safety catch. `cf push -f manifest-docker.yml` run
# by hand fails on the missing variable instead of deploying a stale tag.
#
# The org and space are NOT in the manifests. Cloud Foundry takes them from the
# session, so target them yourself with `cf target -o <org> -s <space>` before
# running this - a deployment should not land wherever a console last pointed.
#
# Usage:
#   scripts/deploy-cf.sh --docker
#   scripts/deploy-cf.sh --buildpack
#   scripts/deploy-cf.sh --docker --dry-run     # print the command, run nothing
#
# The cf CLI v7+ is required: `--strategy rolling` does not exist before it.
# A private registry needs CF_DOCKER_PASSWORD in the environment.
# ---------------------------------------------------------------------------

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

load_config

MODE=""
DRY_RUN=0
STRATEGY="rolling"

while [ $# -gt 0 ]; do
  case "$1" in
    --docker)    MODE="docker" ;;
    --buildpack) MODE="buildpack" ;;
    --dry-run)   DRY_RUN=1 ;;
    --strategy)  STRATEGY="${2:?--strategy needs a value}"; shift ;;
    -h|--help)   usage "${BASH_SOURCE[0]}"; exit 0 ;;
    *)           die "unknown argument: $1" ;;
  esac
  shift
done

[ -n "$MODE" ] || die "choose one: --docker or --buildpack
     scripts/deploy-cf.sh --help"

need_cmd cf "install the Cloud Foundry CLI v7+ from https://github.com/cloudfoundry/cli"

# v7 is the floor because --strategy rolling does not exist before it, and a
# documentation site should not go dark during an update.
cf_version="$(cf version 2>/dev/null | head -1)"
case "$cf_version" in
  *"version 6."*) die "cf CLI v7 or newer is required, found: $cf_version" ;;
esac
log "cf client  : $cf_version"

if ! cf target >/dev/null 2>&1; then
  die "not logged in to Cloud Foundry
     Run: cf login -a <api-endpoint>, then cf target -o <org> -s <space>"
fi
cf target | sed 's/^/     /'

manifest="$REPO_ROOT/deploy/cf/manifest-$MODE.yml"
[ -f "$manifest" ] || die "manifest not found: $manifest"

# The application name is read back out of the manifest rather than restated
# here, so the manifest stays the only place it is written.
app_name="$(awk '/^[[:space:]]*-[[:space:]]*name:/ {print $3; exit}' "$manifest")"
[ -n "$app_name" ] || die "could not read the application name from $manifest"
log "application: $app_name"

args=(push -f "$manifest")
[ -n "$STRATEGY" ] && args+=(--strategy "$STRATEGY")

if [ "$MODE" = "docker" ]; then
  args+=(--var "docker_image=$IMAGE_REF")
  if [ -n "${REGISTRY_USER:-}" ]; then
    args+=(--docker-username "$REGISTRY_USER")
    # cf reads CF_DOCKER_PASSWORD from the environment. Passing a password as
    # an argument would put it in the process list.
    [ -n "${CF_DOCKER_PASSWORD:-}" ] \
      || die "REGISTRY_USER is set but CF_DOCKER_PASSWORD is not - export it, do not pass it as an argument"
  fi
else
  "$REPO_ROOT/scripts/docs.sh package-cf"
fi

step "cf ${args[*]}"

if [ "$DRY_RUN" -eq 1 ]; then
  ok "dry run - nothing was pushed"
  exit 0
fi

cf "${args[@]}"

echo
ok "deployed"
cf app "$app_name" 2>/dev/null | head -20 || true
