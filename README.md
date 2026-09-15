# mkdocsgo-example

An example [MkDocs](https://www.mkdocs.org/) documentation repository served by
**[mkdocsgo](https://github.com/kinjelom/mkdocsgo)**: one static Go binary that
serves the built site to readers and the Markdown sources to AI agents over the
Model Context Protocol, from a single process and a single port.

Copy this repository, replace `docs/` with your own, and you have a
documentation site that deploys as one image of about 22 MB to Docker, Cloud
Foundry or Kubernetes, with no Python, no nginx and no shell in the result.

> The documentation this repository serves is **about** this arrangement, so
> the fastest way to read it is to run it: `scripts/run.sh`, then open
> <http://127.0.0.1:8000/>.

## Quick start

Docker (or podman) is the only prerequisite. The documentation toolchain runs
in the pinned [mkdocs-build-toolbox](https://github.com/kinjelom/mkdocs-build-toolbox)
image, and the server binary downloads itself when the package is assembled -
there is nothing to install.

```bash
scripts/docs.sh serve    # mkdocs serve  - write, with live reload
scripts/run.sh      # mkdocsgo      - see exactly what will be deployed
scripts/image.sh    # docker build  - the artefact that gets deployed
```

| Endpoint                        | What            |
|---------------------------------|-----------------|
| <http://127.0.0.1:8000/>        | the site        |
| <http://127.0.0.1:8000/mcp>     | MCP, for agents |
| <http://127.0.0.1:8000/healthz> | liveness        |

Every script takes `--help`. The walkthrough, and what each task needs
installed: [docs/getting-started.md](docs/getting-started.md).

## How this depends on mkdocsgo

On a released version, pinned in one line of `project.conf`:

```ini
MKDOCSGO_VERSION=0.2.0
```

`scripts/docs.sh package-cf` downloads that release and verifies its SHA-256 before
installing it; the `Dockerfile` uses the matching release image as a build
stage. Both read the same line, so the version you run locally and the version
in the image cannot disagree.

The full reasoning, with the comparison table:
**[docs/guides/depending-on-mkdocsgo.md](docs/guides/depending-on-mkdocsgo.md)**.

## Deploying

The manifests are real files, which the documentation pages include with
`--8<--` rather than restate - so a documented manifest cannot drift from the
deployed one.

| Target                            | Files                                                                    | Guide                                                                |
|-----------------------------------|--------------------------------------------------------------------------|----------------------------------------------------------------------|
| Docker                            | [`Dockerfile`](./Dockerfile)                                             | [docs/deployment/docker.md](docs/deployment/docker.md)               |
| Cloud Foundry, Docker application | [`deploy/cf/manifest-docker.yml`](./deploy/cf/manifest-docker.yml)       | [docs/deployment/cloud-foundry.md](docs/deployment/cloud-foundry.md) |
| Cloud Foundry, binary buildpack   | [`deploy/cf/manifest-buildpack.yml`](./deploy/cf/manifest-buildpack.yml) | [docs/deployment/cloud-foundry.md](docs/deployment/cloud-foundry.md) |
| Kubernetes                        | [`deploy/k8s/`](./deploy/k8s/)                                           | [docs/deployment/kubernetes.md](docs/deployment/kubernetes.md)       |

```bash
scripts/image.sh --push             # publish the documentation image
scripts/deploy-cf.sh --docker       # Cloud Foundry, from the registry
scripts/deploy-cf.sh --buildpack    # Cloud Foundry, no registry needed
kubectl apply -f deploy/k8s/        # Kubernetes
```

## Who may read it

`mkdocsgo.yml` maps the addresses this documentation answers on to zones. Here
the loopback addresses and the internal route are public, and the outward-facing
ones ask for credentials - a password from a browser, a bearer token from an
agent. Delete the file and every address is public again, which is the default.

Nothing in it is a secret: a password is an Argon2id hash and a token a SHA-256
digest. The demonstration credentials it ships with are published on purpose,
and guard reserved example domains.

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8000/               # 200
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: docs.example.com' \
  http://127.0.0.1:8000/                                                     # 401
```

How it works, and how to replace those credentials:
[docs/guides/restricting-access.md](docs/guides/restricting-access.md).

## Layout

`project.conf` answers two questions: which mkdocsgo this runs on, and what
image this repository publishes. `mkdocsgo.yml` answers a third: which address
gets which policy. Everything else is an ordinary MkDocs project plus
`scripts/` and `deploy/`.

The annotated tree, and the list of things that must agree with each other:
[docs/reference/project-layout.md](docs/reference/project-layout.md).

`site/` and `dist/` are generated and git-ignored. A
fresh clone rebuilds every one of them.

## Related

- **[kinjelom/mkdocsgo](https://github.com/kinjelom/mkdocsgo)** - the server
  itself: [what it does](https://github.com/kinjelom/mkdocsgo#readme),
  [how it works](https://github.com/kinjelom/mkdocsgo/blob/main/ARCHITECTURE.md),
  and [what it replaces](https://github.com/kinjelom/mkdocsgo/blob/main/COMPARISON.md).

## Licence

[MIT](./LICENSE), the same as
[mkdocsgo](https://github.com/kinjelom/mkdocsgo) itself. Copy this repository
and do what you like with it - that is what it is for.
