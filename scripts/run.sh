#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# mkdocsgo-example - run the documentation the way Cloud Foundry will
#
# Serves dist/cf with the pinned mkdocsgo binary that is already in it, on the
# port passed the way the platform passes it:
#
#   http://127.0.0.1:<port>/          the site
#   http://127.0.0.1:<port>/mcp       MCP, for agents
#   http://127.0.0.1:<port>/healthz   liveness
#
# This is the same binary, the same directory and the same command that
# `cf push` stages with the binary buildpack. What you see here is what gets
# deployed - which is not true of `mkdocs serve`.
#
# The package comes from scripts/docs.sh package-cf, which downloads the binary,
# verifies its checksum and assembles it. There is nothing else to install.
#
# Usage:
#   scripts/run.sh                    # package if needed, then serve
#   scripts/run.sh 9000               # another port
#   scripts/run.sh --repackage        # rebuild dist/cf first
# ---------------------------------------------------------------------------

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$REPO_ROOT/dist/cf"

die() { printf '\033[31mERROR\033[0m %s\n' "$*" >&2; exit 1; }
log() { printf '\033[36m==>\033[0m %s\n' "$*"; }

PORT="$(sed -n 's/^LOCAL_PORT=//p' "$REPO_ROOT/project.conf" | head -1)"
REPACKAGE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --repackage) REPACKAGE=1 ;;
    -h|--help)   sed -n '2,/^# ---/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    ''|*[!0-9]*) die "unknown argument: $1" ;;
    *)           PORT="$1" ;;
  esac
  shift
done

if [ "$REPACKAGE" -eq 1 ] || [ ! -x "$DIST/mkdocsgo" ]; then
  "$REPO_ROOT/scripts/docs.sh package-cf"
fi

log "site       : http://127.0.0.1:${PORT:-8000}/"
log "mcp        : http://127.0.0.1:${PORT:-8000}/mcp"
log "healthz    : http://127.0.0.1:${PORT:-8000}/healthz"
log "stop       : Ctrl-C"
echo

# No -http: mkdocsgo listens on $PORT when given no address, which is exactly
# how Cloud Foundry starts it.
cd "$DIST"
PORT="${PORT:-8000}" exec ./mkdocsgo -mode site+mcp -project .
