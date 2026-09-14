# mkdocsgo example

This is an ordinary [MkDocs](https://www.mkdocs.org/) project. What makes it an
example is how it is *served*: by
[mkdocsgo](https://github.com/kinjelom/mkdocsgo), a single static Go binary
that answers both audiences from one process and one port.

**Readers** get the site at `/`: the same HTML `mkdocs build` produced, with
content-hash ETags, compression done once at startup, and a cache policy that
does not need an `nginx.conf`.

**Agents** get the Model Context Protocol at `/mcp`: the Markdown sources,
indexed by section, so an assistant retrieves the one relevant heading rather
than a four-thousand-line page.

Python builds the site. Python is not in the result.

## What this repository shows

| | |
|---|---|
| How to depend on mkdocsgo without vendoring it | [How to depend on it](guides/depending-on-mkdocsgo.md) |
| Writing pages that both a reader and an agent can use | [Writing for humans and agents](guides/writing-for-agents.md) |
| The three-stage image, and what does not reach the last stage | [Docker](deployment/docker.md) |
| Two ways onto Cloud Foundry, with both manifests | [Cloud Foundry](deployment/cloud-foundry.md) |
| A Deployment, a Service and an Ingress | [Kubernetes](deployment/kubernetes.md) |
| Every flag, and which ones matter where | [Command line](reference/cli.md) |
| What the server actually reads | [Project layout](reference/project-layout.md) |

## Three commands

```bash
scripts/docs.sh serve    # mkdocs serve  - write, with live reload
scripts/run.sh      # mkdocsgo      - see exactly what will be deployed
scripts/image.sh    # docker build  - the artefact that gets deployed
```

The full walkthrough is in [Getting started](getting-started.md).

!!! note "Two servers, two jobs"

    `mkdocs serve` rebuilds on every keystroke and is the authoring loop.
    mkdocsgo reads the project once at startup and is the deployment. Neither
    replaces the other, and using the wrong one is the most common confusion
    when starting out.
