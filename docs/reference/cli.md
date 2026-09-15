# Command line

Every flag mkdocsgo takes, and which ones matter in which deployment.

## Modes

```bash
mkdocsgo -mode site+mcp -project . -http 0.0.0.0:8080   # default
mkdocsgo -mode site     -project . -http 0.0.0.0:8080   # a static file server
mkdocsgo -mode mcp      -project . -http 0.0.0.0:8080   # MCP over HTTP
mkdocsgo -mode mcp      -project .                      # MCP over stdio
```

| Mode | `/` | `/mcp` | `/healthz` |
|---|---|---|---|
| `site+mcp` | the built site | MCP | yes |
| `site` | the built site | - | yes |
| `mcp` | - | MCP | yes |

`mcp` with no `-http` serves over stdio instead, which is what a local MCP
client launches. Every other mode needs an address.

`-mode` decides which branch is registered at all - neither is a runtime check,
so `-mode site` does not have a disabled MCP endpoint, it has none.

## Flags

| Flag | Default | Meaning |
|---|---|---|
| `-mode` | `site+mcp` | What to serve |
| `-project` | `.` | Directory holding `mkdocs.yml` |
| `-site-dir` | `<project>/site` | The built site |
| `-config` | `<project>/mkdocsgo.yml` | Zones; absent means every address is public |
| `-http` | *(empty)* | Address to listen on |
| `-search-limit` | `8` | Default search results; callers may override, capped at 50 |
| `-allow-origin` | - | Additional allowed `Origin` for `/mcp`; repeatable |
| `-no-resources` | `false` | MCP tools only, no per-page resources |
| `-no-access-log` | `false` | Do not log HTTP requests |
| `-version` | | Print the version and exit |
| `-healthcheck <url>` | | GET the URL, exit 0 on 2xx, then quit. `self` means this server's own `/healthz` |
| `-mcp-probe <url>` | | Ask an MCP endpoint for its tool list, exit 0 if it answers |
| `-new-token` | | Mint a bearer token, print it and the line to paste, then quit |
| `-hash-password` | | Hash a password for `mkdocsgo.yml`, then quit |

## Ports

`-http` wins. Without it the server reads `$DOC_PORT`, then `$PORT`, and binds
`0.0.0.0` on whichever it finds.

That order is what lets one binary run unchanged everywhere:

| Platform | What sets the port | What the command says |
|---|---|---|
| Docker | you do, with `-p` and `DOC_PORT` | `-http 0.0.0.0:8080` |
| Cloud Foundry | the platform, per instance | nothing - `$PORT` is read |
| Kubernetes | you do, in `containerPort` | `-http 0.0.0.0:8080` |

Nothing has to expand a variable in a shell, which matters because the runtime
image has no shell to expand it.

## Probing a running server

The runtime image is distroless: no `curl`, no `wget`, no shell. The binary is
what issues the requests.

```bash
# is it serving?
docker exec <container> /mkdocsgo -healthcheck self

# is a particular page there?
docker exec <container> /mkdocsgo -healthcheck http://127.0.0.1:8080/reference/cli/

# are the MCP tools reachable? (/mcp answers POST - a GET tells you nothing)
docker exec <container> /mkdocsgo -mcp-probe http://127.0.0.1:8080/mcp
```

`-healthcheck self` resolves the port from `$DOC_PORT`/`$PORT` inside the
binary, so a Docker `HEALTHCHECK` in exec form works without a shell.

## MCP tools

Four, all annotated read-only and idempotent.

| Tool | Returns |
|---|---|
| `search_docs` | Best matching **sections**, each with breadcrumb, anchor, snippet and score |
| `get_section` | One section as Markdown - the cheap way to read |
| `get_page` | A whole page as its original Markdown, plus its heading list |
| `list_pages` | Every page with breadcrumb and heading count; `prefix` filters |

A bad path or anchor comes back as a *tool* error with a hint, not a protocol
error, so a model can correct itself instead of failing the turn.

Each page is also an MCP resource at `docs://<path>` serving the source
Markdown. `-no-resources` turns that off; the tools remain, because every
client implements tools and resource support is uneven.

## Zones

With an `mkdocsgo.yml` beside `mkdocs.yml`, the address a request arrived at
decides what it needs. Without one - the default - every address is public and
nothing below applies.

| | |
|---|---|
| `access: public` | served to anyone, as before |
| `access: restricted` | a browser needs HTTP Basic credentials, an agent a bearer token |
| `access: off` | `403` to everything, retiring an address without touching DNS |
| an address no zone claims | `403` |

`/healthz` is outside every zone, because a platform probe arrives at the
container's address rather than at a route. So is the metadata document at
`/.well-known/oauth-protected-resource/mcp`, which a client reads in order to
learn how to authenticate.

Configuration errors stop the server rather than surfacing as a puzzling `401`
later: a restricted zone with no principals, a plaintext password where a hash
belongs, one host claimed twice, an unknown key.

This repository's zones, and how to try them:
[Restricting access by address](../guides/restricting-access.md).

## Origin and `/mcp`

`Origin` is validated on `/mcp`. That is DNS-rebinding defence, not access
control: without it, a page a user happens to visit could drive a server bound
to their loopback interface.

- No `Origin` header - every non-browser MCP client - passes.
- Loopback origins pass.
- Anything else gets 403 unless named with `-allow-origin`.

```bash
mkdocsgo -mode site+mcp -project . -http 0.0.0.0:8080 \
  -allow-origin https://agent.example.com
```

The site itself is not origin-guarded; whether it is public is a zone's
business, not the `Origin` header's. The guard runs before the zone check, so a
rebinding attempt never reaches a password hash.
