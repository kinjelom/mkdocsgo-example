#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# mkdocsgo-example - the MCP server over stdio
#
# What a local MCP client launches: no HTTP, no port, JSON-RPC on stdin and
# stdout. Register it with any client that speaks MCP, for example in
# .mcp.json:
#
#   {
#     "mcpServers": {
#       "example-docs": {
#         "command": "scripts/mcp.sh"
#       }
#     }
#   }
#
# stdout carries the protocol, so every message this script prints goes to
# stderr. One stray byte on stdout breaks the client handshake - which is why
# the packaging output is redirected rather than left where it lands.
#
# Deployed, the same server answers over HTTP at /mcp instead; stdio is for
# reading this repository's own documentation while working on it.
#
# Usage:
#   scripts/mcp.sh
# ---------------------------------------------------------------------------

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$REPO_ROOT/dist/cf"

case "${1:-}" in
  -h|--help) sed -n '2,/^# ---/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
  "")        ;;
  *)         printf '\033[31mERROR\033[0m unknown argument: %s\n' "$1" >&2; exit 1 ;;
esac

# The binary and the Markdown sources both come from the package, so an agent
# reading here sees exactly what the deployed server serves.
[ -x "$DIST/mkdocsgo" ] || "$REPO_ROOT/scripts/docs.sh package-cf" >&2

cd "$DIST"
exec ./mkdocsgo -mode mcp -project .
