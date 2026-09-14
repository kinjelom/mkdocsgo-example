# Getting started

Everything below works from a fresh clone. The only prerequisite is Docker or
podman: the documentation toolchain runs in the pinned
[mkdocs-build-toolbox](https://github.com/kinjelom/mkdocs-build-toolbox) image,
and the server binary downloads itself when the package is assembled.

## 1. Write

```bash
scripts/docs.sh serve
```

`mkdocs serve` on <http://127.0.0.1:8000>, with live reload. Edit a file under
`docs/`, save, watch the browser update. This is the authoring loop, and it is
plain MkDocs - nothing in this repository changes how a page is written.

Nothing is installed on your machine. The script starts the pinned
[mkdocs-build-toolbox](https://github.com/kinjelom/mkdocs-build-toolbox) image
with this repository mounted into it; the first run pulls that image, later
ones do not.

## 2. Run it the way it will be deployed

```bash
scripts/run.sh
```

That builds the site with `mkdocs build --strict`, makes sure the pinned
mkdocsgo binary is installed, and serves both halves:

| | |
|---|---|
| <http://127.0.0.1:8000/> | the site |
| <http://127.0.0.1:8000/mcp> | MCP, for agents |
| <http://127.0.0.1:8000/healthz> | liveness |

Same binary, same flags and same two endpoints as the container, the Cloud
Foundry application and the Kubernetes pod. What you see here is what gets
deployed - which is *not* true of `mkdocs serve`.

!!! warning "--strict is not optional"

    `scripts/docs.sh test` builds with `--strict`, so a broken internal link, a
    page missing from the navigation or a snippet that does not resolve fails
    the build. That is deliberate: it is the only check between a typo and a
    published 404.

## 3. Point an agent at it

The MCP endpoint is what this whole arrangement exists for. Over HTTP it is the
`/mcp` URL above. Locally, over stdio - which is what most desktop clients
launch - register `scripts/mcp.sh`:

```json title=".mcp.json"
{
  "mcpServers": {
    "example-docs": {
      "command": "scripts/mcp.sh"
    }
  }
}
```

Four tools appear: `search_docs`, `get_section`, `get_page`, `list_pages`. Ask
the assistant something answered by a page here and watch it retrieve one
section rather than the whole file.

The site does not need to be built for this. The MCP half reads the Markdown in
`docs/`, not the rendered HTML.

### Over HTTP

Over HTTP there is nothing to install on the client side: no binary to
download, no checkout, no Python. A client needs the URL and nothing else,
which is what lets one deployed instance answer for a whole team.

```json title=".mcp.json"
{
  "mcpServers": {
    "example-docs": {
      "type": "http",
      "url": "https://docs.example.com/mcp"
    }
  }
}
```

The URL is the only thing that differs between a local `scripts/run.sh` and the
published site - `http://127.0.0.1:8000/mcp` or `https://docs.example.com/mcp`.
Same endpoint, same four tools.

Claude Code writes that file for you. `--scope user` registers the server for
every project instead of only the current directory, which is usually what
shared documentation wants:

```bash
claude mcp add --transport http example-docs https://docs.example.com/mcp --scope user
claude mcp get example-docs
```

`get` health-checks the server, so a wrong URL surfaces there rather than
halfway through a conversation.

!!! warning "`/mcp` is not authenticated"

    The server prints `no authentication` at startup and means it: whoever
    reaches the URL reads every page. For published documentation that changes
    nothing, since the site beside it is public anyway. For anything internal,
    `/mcp` needs the same protection as the site, applied by whatever sits in
    front of it - see [Kubernetes](deployment/kubernetes.md).

Two things that look like failures and are not. `/mcp` answers POST, so opening
it in a browser shows nothing useful. And `Origin` is validated: a client that
sends no `Origin` header - which is every non-browser MCP client - passes,
while anything running inside a browser needs its origin named with
`-allow-origin` ([Command line](reference/cli.md)).

## 4. Package it

```bash
scripts/image.sh --run
```

Builds the self-contained image and runs it. Three stages go in - Python builds
the site, the mkdocsgo image contributes one file, distroless assembles - and
about 22 MB comes out, with no Python, no shell and no package manager in it.

Where to send it next: [Docker](deployment/docker.md),
[Cloud Foundry](deployment/cloud-foundry.md),
[Kubernetes](deployment/kubernetes.md).

## The scripts

| Script | Does |
|---|---|
| `scripts/docs.sh serve` | `mkdocs serve`, live reload - the authoring loop |
| `scripts/run.sh` | build, then serve site + MCP with the real binary |
| `scripts/mcp.sh` | MCP over stdio, for a local client |
| `scripts/image.sh` | build, run or push the documentation image |
| `scripts/docs.sh package-cf` | assemble `dist/cf/` for the binary buildpack |
| `scripts/deploy-cf.sh` | `cf push`, either way |

Every one takes `--help`, which prints its own header comment.

## What each task needs

| Task | Needs |
|------|-------|
| everything | Docker or podman - the toolchain lives in the toolbox image |
| `run`, `mcp` | `curl` and `tar` - the pinned binary is downloaded, not compiled |
| `image` | Docker or podman |
| `package-cf` | Docker or podman - the site build, `curl` and `tar` all run inside the toolbox image |
| `deploy-cf` | Cloud Foundry CLI **v7 or newer** |

No Go toolchain, anywhere. That is the point of depending on a release rather
than on a source tree - see [How to depend on it](guides/depending-on-mkdocsgo.md).

## Upgrading mkdocsgo

Change one line in `project.conf`:

```ini
MKDOCSGO_VERSION=0.2.0
```

Then run `scripts/run.sh`. It notices the pinned version and the installed one
disagree, downloads the new release, verifies its checksum and uses it. Commit
the changed line - that diff is the entire upgrade record.

Why it is pinned rather than tracking the latest:
[How to depend on it](guides/depending-on-mkdocsgo.md).
