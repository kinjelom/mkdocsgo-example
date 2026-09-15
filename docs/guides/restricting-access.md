# Restricting access by address

One documentation set, two kinds of address: an intranet route everyone inside
may read, and an internet route only named people and agents may. That is what
zones do, and this repository has one of each.

## What a zone is

A **zone** is a policy for an address. Several addresses may share one, and
every address the server answers on must belong to one - an address no zone
claims gets `403`.

A zone is **not** a filter over content.

!!! warning "Every zone serves the same pages"

    A restricted zone hides nothing from someone who knows a public zone's
    address for the same deployment. It asks who you are; it does not change
    what there is to read.

    Documentation that must genuinely differ is a separate build and a separate
    deployment - a different `exclude_docs`, a different image, a different
    route. Filtering at request time would have to rewrite Material's
    `search_index.json` and the sitemap as well, and a half-filtered search
    index leaks exactly what it claims to hide.

## This repository's file

`mkdocsgo.yml` sits beside `mkdocs.yml` and is read at startup. Delete it and
every address is public again; that is the default and the only thing zones
change.

```yaml title="mkdocsgo.yml"
--8<-- "mkdocsgo.yml"
```

Nothing in it is a secret. A password is an Argon2id hash, a token is a SHA-256
digest, and the secrets behind them were printed once. That is the whole reason
the file can live in a repository with no encryption to manage.

## Trying it locally

`scripts/run.sh` serves on `127.0.0.1`, which the `intranet` zone claims, so the
local experience is unchanged:

```bash
scripts/run.sh
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8000/       # 200
```

The restricted zone is reachable by claiming its address:

```bash
# No credentials: a challenge.
curl -i -H 'Host: docs.example.com' http://127.0.0.1:8000/ | head -3
# HTTP/1.1 401 Unauthorized
# WWW-Authenticate: Basic realm="mkdocsgo example (demonstration credentials)"

# With them: the page.
curl -s -o /dev/null -w '%{http_code}\n' -u demo:demo \
  -H 'Host: docs.example.com' http://127.0.0.1:8000/                  # 200
```

And for an agent, on `/mcp`, with the demonstration token:

```bash
curl -s -X POST http://<this-machine>:8000/mcp \
  -H 'Host: docs.example.com' \
  -H 'Authorization: Bearer mkd_9OCKzGt5lEwewmcpigJdvud-tNFvwu5mwwIFb4JDXVs' \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
```

!!! note "Why `<this-machine>` and not `127.0.0.1`"

    The MCP SDK refuses a request that reaches a **loopback** listener carrying
    a non-loopback `Host` - its own DNS-rebinding defence, unrelated to zones.
    Over the machine's real address, or in any real deployment, it does not
    apply. The site half is unaffected.

An agent is configured with the same header:

```json
{ "mcpServers": { "example-docs": {
  "type": "http",
  "url": "https://docs.example.com/mcp",
  "headers": { "Authorization": "Bearer mkd_…" }
}}}
```

!!! danger "These credentials are published"

    `demo` / `demo` and the token above are in this repository so that it can be
    read and run as an example. The addresses they guard are reserved
    documentation domains nobody can deploy to. Replace both before this
    becomes a real deployment.

## Your own credentials

The server mints them; a hash is not something to assemble by hand.

```bash
mkdocsgo -new-token       # prints the secret once, and the lines to paste
mkdocsgo -hash-password   # prompts twice, prints the hash
```

The binary is in `dist/cf/` after `scripts/docs.sh package-cf`, so
`dist/cf/mkdocsgo -new-token` works with nothing else installed.

**Rotating a token** is adding a second entry under the same principal and
removing the first once every client has moved. Both work at once, so nothing
has to go down for it, and the `id` is what the access log prints - which is how
you tell whether the old one is still in use before deleting it.

## What a restricted zone changes

| | |
|---|---|
| A browser with no credentials | `401` and the password prompt |
| An agent with no token | `401` and a `WWW-Authenticate: Bearer` challenge pointing at `/.well-known/oauth-protected-resource/mcp` |
| Every served response | `Cache-Control` becomes `private`, plus `X-Robots-Tag: noindex, nofollow` |
| The access log | gains `zone=internet principal=demo/password` |
| `/healthz` | unchanged, and outside every zone - otherwise no platform probe would ever pass |

## Deploying with zones

Two things to keep in view:

- **Every route needs a line in `hosts:`.** The routes in
  `deploy/cf/manifest-*.yml` and the host in `deploy/k8s/ingress.yaml` all
  appear in `mkdocsgo.yml`, because an address no zone claims answers `403`.
  Adding a route to a manifest without adding it here deploys a site nobody can
  read - which is the failure this design prefers to the alternative.
- **A restricted zone wants more memory.** Verifying an Argon2id password costs
  19 MiB, two at a time. The Cloud Foundry manifests allocate 192 MiB for that
  reason; 128 MiB was enough while every zone was public.

TLS still terminates in front - the Cloud Foundry router, the Ingress. Basic
auth over plain HTTP is a password in clear text, and the server cannot detect
that it is being used that way.

## Later: Keycloak

`method:` in a zone is the seam. Today it has one value, `static`, which
verifies against the hashes in the file. When it becomes `oidc`, the agent half
changes verifier - a JWT checked against the realm's JWKS, with the audience
required to name this server - and the rest of the file does not move. The
`401` already points at the metadata document that will name the authorization
server, so a client that follows the pointer needs no change.

The whole format, and what is deliberately not in it, is in
[AUTH.md](https://github.com/kinjelom/mkdocsgo/blob/main/AUTH.md).
