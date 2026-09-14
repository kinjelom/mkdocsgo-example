#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# mkdocsgo-example - shared shell helpers
#
# Sourced by every scripts/*.sh. Never executed directly.
#   . "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# ---------------------------------------------------------------------------

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$REPO_ROOT/project.conf}"
MKDOCS_YML="${MKDOCS_YML:-$REPO_ROOT/mkdocs.yml}"
VENV_DIR="${VENV_DIR:-$REPO_ROOT/.venv}"
SITE_DIR="${SITE_DIR:-$REPO_ROOT/site}"
MKDOCSGO_DIR="${MKDOCSGO_DIR:-$REPO_ROOT/.mkdocsgo}"

# --- Output ----------------------------------------------------------------

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_INFO=$'\033[36m'; C_OK=$'\033[32m'
  C_WARN=$'\033[33m'; C_ERR=$'\033[31m'; C_BOLD=$'\033[1m'
else
  C_RESET=''; C_INFO=''; C_OK=''; C_WARN=''; C_ERR=''; C_BOLD=''
fi

log()   { printf '%s==>%s %s\n' "$C_INFO" "$C_RESET" "$*"; }
ok()    { printf '%s  OK%s %s\n' "$C_OK" "$C_RESET" "$*"; }
warn()  { printf '%sWARN%s %s\n' "$C_WARN" "$C_RESET" "$*" >&2; }
die()   { printf '%sERROR%s %s\n' "$C_ERR" "$C_RESET" "$*" >&2; exit 1; }
step()  { printf '\n%s%s%s\n' "$C_BOLD" "$*" "$C_RESET"; }

# Print the header comment block of the calling script as its --help text.
usage() {
  local file="${1:-${BASH_SOURCE[1]}}"
  awk '
    NR == 1 && /^#!/ { next }
    /^#/             { sub(/^# ?/, ""); if ($0 !~ /^-+$/) print; next }
                     { exit }
  ' "$file"
}

# --- Configuration ---------------------------------------------------------

# Read a scalar from the top-level `extra:` block of mkdocs.yml, without a YAML
# parser: the key is a scalar two spaces in, which is the whole grammar needed
# here. That block is where the documentation's own version lives - the file
# the documentation is built from, rather than a second copy in project.conf.
mkdocs_extra() {
  local key="$1" value
  value="$(awk -v key="  $key:" '
    $0 == "extra:"            { inside = 1; next }
    inside && /^[^[:space:]]/ { exit }
    inside && index($0, key) == 1 { print substr($0, length(key) + 1); exit }
  ' "$MKDOCS_YML")"
  value="${value%$'\r'}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  value="${value%\"}"; value="${value#\"}"
  value="${value%\'}"; value="${value#\'}"
  printf '%s' "$value"
}

# Parse project.conf into shell variables. Parsed line by line rather than
# sourced, so values are literal and nothing in the file can execute code.
# Values already in the environment win.
load_config() {
  [ -f "$CONFIG_FILE" ] || die "configuration file not found: $CONFIG_FILE"

  local line key value lineno=0
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    line="${line%$'\r'}"
    case "$line" in ''|'#'*) continue ;; esac
    case "$line" in
      *=*) ;;
      *) die "$CONFIG_FILE:$lineno: expected KEY=VALUE, got: $line" ;;
    esac
    key="${line%%=*}"
    value="${line#*=}"
    key="$(printf '%s' "$key" | tr -d '[:space:]')"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    case "$key" in
      ''|*[!A-Za-z0-9_]*) die "$CONFIG_FILE:$lineno: invalid key: $key" ;;
    esac
    [ "$value" = "none" ] && value=""
    if [ -z "${!key:-}" ]; then
      printf -v "$key" '%s' "$value"
    fi
    export "$key"
  done < "$CONFIG_FILE"

  : "${MKDOCSGO_VERSION:?MKDOCSGO_VERSION missing from $CONFIG_FILE}"
  : "${MKDOCSGO_REPO:=kinjelom/mkdocsgo}"
  : "${MKDOCSGO_IMAGE:=ghcr.io/kinjelom/mkdocsgo}"
  : "${IMAGE_NAME:?IMAGE_NAME missing from $CONFIG_FILE}"
  : "${LOCAL_PORT:=8000}"
  : "${CONTAINER_PORT:=8080}"
  : "${IMAGE_LATEST_TAG:=}"

  # The version is not a configuration key. It belongs to the documentation, so
  # it is read from mkdocs.yml - and the tag, the OCI version label and the
  # Cloud Foundry manifest variable are then all the same number the published
  # pages carry in their own footer.
  APP_VERSION="$(mkdocs_extra app_version)"
  [ -n "$APP_VERSION" ] || die "mkdocs.yml: extra.app_version is not set
     That is where this documentation's version is written; the image tag is
     read from it."
  IMAGE_VERSION="$APP_VERSION"

  IMAGE_REPO="$(compose_repo)"
  IMAGE_REF="$IMAGE_REPO:$IMAGE_VERSION"
  export APP_VERSION IMAGE_VERSION IMAGE_REPO IMAGE_REF
}

compose_repo() {
  local repo=""
  if [ -n "${REGISTRY:-}" ]; then repo="$REGISTRY/"; fi
  if [ -n "${IMAGE_NAMESPACE:-}" ]; then repo="$repo$IMAGE_NAMESPACE/"; fi
  printf '%s%s' "$repo" "$IMAGE_NAME"
}

print_config() {
  log "mkdocsgo   : $MKDOCSGO_VERSION"
  log "image      : $IMAGE_REF"
  [ -n "$IMAGE_LATEST_TAG" ] && log "extra tag  : $IMAGE_REPO:$IMAGE_LATEST_TAG"
  log "config     : $CONFIG_FILE"
  return 0
}

# --- Tooling ---------------------------------------------------------------

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1${2:+ ($2)}"
}

resolve_docker() {
  if [ -n "${DOCKER:-}" ]; then
    command -v "$DOCKER" >/dev/null 2>&1 || die "DOCKER is set to '$DOCKER' but it is not on PATH"
  elif command -v docker >/dev/null 2>&1; then
    DOCKER=docker
  elif command -v podman >/dev/null 2>&1; then
    DOCKER=podman
  else
    die "neither docker nor podman found on PATH"
  fi
  export DOCKER
}
