# Project layout

What mkdocsgo reads, what it ignores, and what each file in this repository is
for.

## What the server reads

```
/project
|-- mkdocs.yml      site_name, docs_dir, exclude_docs, nav
|-- docs/           every .md - the MCP index
\-- site/           the built site - what browsers get
```

Three things, and only three. There is no configuration file of its own, no
database and no cache directory.

| From `mkdocs.yml` | Used for |
|---|---|
| `site_name` | The MCP server's name, as a client displays it |
| `docs_dir` | Where to find the Markdown |
| `exclude_docs` | What not to index |
| `nav` | The breadcrumb shown beside every search hit |

Everything else in `mkdocs.yml` - theme, plugins, extensions - is MkDocs'
business and is ignored. `mkdocs.yml` is decoded as a YAML node tree rather than
a map, so `!!python/name:` tags and nav ordering both survive.

### What it does not do

It never runs MkDocs. No plugins load, no macros evaluate, no HTML renders. Two
consequences worth knowing:

- A `--8<--` snippet include is indexed **literally**. The published site is
  unaffected - MkDocs expanded it at build time - but a value that exists only
  inside an included file will not be found by a search. See
  [Writing for humans and agents](../guides/writing-for-agents.md).
- `exclude_docs` is honoured for the common cases: one pattern per line,
  directory prefixes and shell globs. Negation (`!`) is ignored rather than
  half-implemented, because getting it wrong would index *more* than you asked
  for.

### Everything is read once

Project and site are loaded at startup and never re-read. Editing a page changes
nothing until a restart - which is the same lifecycle as the image carrying it,
so in a container deployment it costs nothing.

That is also why `mkdocs serve` remains the authoring loop. The two servers are
not alternatives.

## This repository

```
mkdocsgo-example/
|-- project.conf            which mkdocsgo, which toolbox, what this publishes
|-- mkdocs.yml              site config, nav, validation rules, the version
|-- Dockerfile              three stages; Python never reaches the third
|-- docs/                   the documentation content
|-- deploy/
|   |-- cf/                 Cloud Foundry manifests: Docker and buildpack
|   \-- k8s/                Deployment, Service, Ingress
\-- scripts/
    |-- docs.sh             the only `docker run` - the toolbox wrappers call it
    |-- test.sh             checks, mkdocs build --strict, checks
    |-- serve.sh            mkdocs serve - the authoring loop
    |-- package-cf.sh       assemble dist/cf for the binary buildpack
    |-- run.sh              serve dist/cf the way Cloud Foundry will
    |-- mcp.sh              MCP over stdio, for a local client
    |-- lib.sh              config parser, for the two scripts below
    |-- image.sh            build, run or push the documentation image
    \-- deploy-cf.sh        cf push, either way
```

### Generated, never committed

| Path | Made by |
|---|---|
| `site/` | `scripts/docs.sh test` |
| `dist/cf/` | `scripts/docs.sh package-cf` |

Both are in `.gitignore`. A fresh clone produces them from the committed files,
the pinned toolbox image and a pinned download - there is nothing to install
first.

## `project.conf`

One file, two questions.

```ini
# 1. WHICH mkdocsgo does this documentation run on?
MKDOCSGO_VERSION=0.1.1
MKDOCSGO_REPO=kinjelom/mkdocsgo
MKDOCSGO_IMAGE=ghcr.io/kinjelom/mkdocsgo

# 2. WHAT image does this repository publish?
REGISTRY=ghcr.io
IMAGE_NAMESPACE=kinjelom
IMAGE_NAME=mkdocsgo-example
```

There is no version in it. The version of this documentation is
`extra.app_version` in `mkdocs.yml`, which is where the documentation itself
is configured - and the image tag, the OCI version label and the Cloud Foundry
manifest variable are all read from there:

```yaml title="mkdocs.yml"
extra:
  app_version: 0.1.0
```

One number, in the file the pages are built from, so a published image cannot
claim a version the pages inside it disagree with.

It is **parsed, never sourced**: values are taken literally, so nothing in the
file can execute code. Every key must have a value; the literal `none` means
"not set". The environment beats the file, everywhere - which is what lets CI
publish somewhere else, or a developer override a port for one run, without
editing a committed file:

```bash
LOCAL_PORT=9000 scripts/run.sh
IMAGE_NAMESPACE=acme scripts/image.sh --push
```

Credentials are never in it. They come from the environment:
`REGISTRY_USER` / `REGISTRY_PASSWORD`, `GITHUB_TOKEN` for ghcr.io,
`CF_DOCKER_PASSWORD` for a Cloud Foundry Docker push.

## Things that must agree

A short list, because each of these is a mismatch that fails at run time rather
than at build time:

| This | Must match | Or |
|---|---|---|
| `CONTAINER_PORT` in `project.conf` | `EXPOSE` in the `Dockerfile` | the published port serves nothing |
| `CONTAINER_PORT` | `DOC_PORT` in `manifest-docker.yml` | every request 502s |
| `CONTAINER_PORT` | `containerPort` in `deployment.yaml` | the probes fail |
| `MKDOCSGO_VERSION` | what `dist/cf/.version` records | the checks fail until you re-package |
| `extra.app_version` in `mkdocs.yml` | nothing - it is the only copy | (that is the point) |
| Every page | an entry in `nav:` | `--strict` fails the build, by design |
