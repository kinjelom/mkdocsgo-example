#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# mkdocsgo-example - build, run and publish the documentation image
#
# The image is self-contained: the site, the Markdown sources and the server,
# with no Python and no shell. Nothing is built at run time and nothing is
# fetched from the network - which is what makes it the same artefact in every
# environment.
#
# The pinned versions come from project.conf and are passed in as build
# arguments, so the Dockerfile never has to be edited to move a version.
#
# Usage:
#   scripts/image.sh                  # build
#   scripts/image.sh --run            # build, then run it on LOCAL_PORT
#   scripts/image.sh --push           # build, then push version + latest
#
# Credentials come from the environment: REGISTRY_USER / REGISTRY_PASSWORD,
# or GITHUB_TOKEN for ghcr.io.
# ---------------------------------------------------------------------------

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

load_config

RUN_IT=0
PUSH=0
while [ $# -gt 0 ]; do
  case "$1" in
    --run)     RUN_IT=1 ;;
    --push)    PUSH=1 ;;
    -h|--help) usage "${BASH_SOURCE[0]}"; exit 0 ;;
    *)         die "unknown argument: $1" ;;
  esac
  shift
done

resolve_docker

step "Image $IMAGE_REF"
print_config
log "engine     : $DOCKER"

tags=(--tag "$IMAGE_REF")
[ -n "$IMAGE_LATEST_TAG" ] && tags+=(--tag "$IMAGE_REPO:$IMAGE_LATEST_TAG")

cd "$REPO_ROOT"
"$DOCKER" build \
  --build-arg "TOOLBOX_IMAGE=${TOOLBOX_IMAGE}" \
  --build-arg "MKDOCSGO_IMAGE=${MKDOCSGO_IMAGE}:${MKDOCSGO_VERSION}" \
  --build-arg "RUNTIME_IMAGE=${RUNTIME_BASE_IMAGE:-gcr.io/distroless/static-debian12:nonroot}" \
  --build-arg "IMAGE_VERSION=${IMAGE_VERSION}" \
  "${tags[@]}" .

ok "built $IMAGE_REF"
"$DOCKER" image inspect "$IMAGE_REF" --format 'size: {{.Size}} bytes' 2>/dev/null || true

if [ "$RUN_IT" -eq 1 ]; then
  step "Run"
  log "site       : http://127.0.0.1:$LOCAL_PORT/"
  log "mcp        : http://127.0.0.1:$LOCAL_PORT/mcp"
  log "stop with  : Ctrl-C"
  exec "$DOCKER" run --rm \
    --publish "$LOCAL_PORT:$CONTAINER_PORT" \
    --env "DOC_PORT=$CONTAINER_PORT" \
    --name "$IMAGE_NAME-local" \
    "$IMAGE_REF"
fi

if [ "$PUSH" -eq 1 ]; then
  step "Push"
  host="${REGISTRY:-docker.io}"
  user="${REGISTRY_USER:-}"
  password="${REGISTRY_PASSWORD:-}"
  if [ -z "$password" ] && [ "$host" = "ghcr.io" ] && [ -n "${GITHUB_TOKEN:-}" ]; then
    user="${user:-${IMAGE_NAMESPACE:-}}"
    password="$GITHUB_TOKEN"
  fi
  if [ -n "$user" ] && [ -n "$password" ]; then
    # stdin, never an argument: an argument is visible in the process list.
    printf '%s' "$password" | "$DOCKER" login "$host" --username "$user" --password-stdin >/dev/null \
      || die "login to $host failed"
    ok "authenticated to $host as $user"
  else
    warn "no credentials in the environment - assuming '$DOCKER' is already logged in to $host"
  fi

  "$DOCKER" push "$IMAGE_REF"
  ok "pushed $IMAGE_REF"
  if [ -n "$IMAGE_LATEST_TAG" ]; then
    "$DOCKER" push "$IMAGE_REPO:$IMAGE_LATEST_TAG"
    ok "pushed $IMAGE_REPO:$IMAGE_LATEST_TAG"
  fi
fi
