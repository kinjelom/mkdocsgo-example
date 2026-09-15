# Docker

One image holds the documentation and the server. Nothing is built at run time
and nothing is fetched from the network, which is what makes it the same
artefact in every environment.

```bash
scripts/image.sh          # build
scripts/image.sh --run    # build, then run it on http://127.0.0.1:8000
scripts/image.sh --push   # build, then publish version + latest
```

## Three stages, and what does not reach the last one

```
1. site      python:3.13-slim    mkdocs build --strict  ->  /site
2. server    ghcr.io/kinjelom/mkdocsgo:<pinned>         ->  /mkdocsgo
3. runtime   distroless/static   the binary + /project
```

Stage 1 installs the whole MkDocs toolchain and then disappears. Stage 2 exists
only to contribute one file. What ships is stage 3: a binary, the built site,
and the Markdown sources the MCP index is built from - about 22 MB, with no
Python, no Node, no shell and no package manager.

The Markdown sources are there because the MCP half indexes the author's
original text rather than rendered HTML. They are a fraction of the size of
`site/`.

```dockerfile title="Dockerfile"
--8<-- "Dockerfile"
```

## Why no shell

`gcr.io/distroless/static-debian12:nonroot` contains a CA bundle, timezone data
and nothing else. That removes most of what a vulnerability scanner would
otherwise find, because most of it is packages that are not there.

The cost is real and worth stating: you cannot `docker exec ... sh` into a running
container to look around. Anything that needs to probe the container calls the
binary instead:

```bash
docker exec <container> /mkdocsgo -healthcheck http://127.0.0.1:8080/
docker exec <container> /mkdocsgo -mcp-probe   http://127.0.0.1:8080/mcp
```

The MCP endpoint answers POST, so a GET against `/mcp` tells you nothing -
`-mcp-probe` asks it for its tool list, which is a real answer.

## The health check

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD ["/mkdocsgo", "-healthcheck", "self"]
```

`self` resolves the port from `$DOC_PORT` or `$PORT` *inside the binary*,
because `HEALTHCHECK` in exec form has no shell to expand a variable - and this
image has no shell to give it.

## Running it

```bash
docker run --rm -p 8000:8080 -e DOC_PORT=8080 ghcr.io/kinjelom/mkdocsgo-example:0.2.1
```

| | |
|---|---|
| <http://127.0.0.1:8000/> | the site |
| <http://127.0.0.1:8000/mcp> | MCP |
| <http://127.0.0.1:8000/healthz> | liveness |

To serve only one half, override the command:

```bash
docker run --rm -p 8000:8080 ghcr.io/kinjelom/mkdocsgo-example:0.2.1 \
  -mode site -project /project -http 0.0.0.0:8080
```

## Without baking anything in

The plain server image carries no content, so a project can be mounted into it.
Useful for a quick look at a site you have already built; not how you deploy.

```bash
scripts/image.sh
docker run --rm -p 8000:8080 -v "$PWD:/project:ro" ghcr.io/kinjelom/mkdocsgo:0.2.0
```

## Build arguments

Every pinned version comes from `project.conf` - except this documentation's
own, which comes from `extra.app_version` in `mkdocs.yml`. `scripts/image.sh`
passes them all in, so the Dockerfile never has to be edited to move one.

| Argument | From | What it pins |
|---|---|---|
| `PYTHON_IMAGE` | `PYTHON_BASE_IMAGE` | the toolchain that builds the site |
| `MKDOCSGO_IMAGE` | `MKDOCSGO_IMAGE:MKDOCSGO_VERSION` | the server |
| `RUNTIME_IMAGE` | `RUNTIME_BASE_IMAGE` | the base the result is assembled on |
| `IMAGE_VERSION` | `extra.app_version` in `mkdocs.yml` | the tag and the OCI version label on the result |

Building by hand with `docker build .` uses the defaults written into the
Dockerfile, which may be older than what `project.conf` says.
