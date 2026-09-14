# Cloud Foundry

Two ways to run the same documentation, and the choice turns on one question:
**does the foundation have a container registry it can pull from?**

```bash
cf login -a <api-endpoint>
cf target -o <org> -s <space>

scripts/deploy-cf.sh --docker      # an image reference
scripts/deploy-cf.sh --buildpack   # a directory of files
```

| | Docker application | Binary buildpack |
|---|---|---|
| Needs a registry | yes | **no** |
| What you push | an image reference | a directory |
| Who builds | your CI | your CI (the site) + CF (the package) |
| Runs on | your image, distroless | the `cflinuxfs4` stack |
| Patching the base | you rebuild and republish | the platform patches the stack |
| Rollback | push an older tag | `cf rollback` to an earlier package |
| Best when | you already publish images | you do not, or the registry is unreachable |

Both end up as the same process listening on `$PORT`, serving the site at `/`,
MCP at `/mcp` and liveness at `/healthz`.

## The org and space are not in the manifests

Cloud Foundry takes them from the session. Target them yourself before
deploying:

```bash
cf target -o docs -s production
```

Leaving them out of the manifest is deliberate: a manifest that names a space
deploys to that space regardless of what the operator thought they were doing,
and a manifest that does not cannot land somewhere unintended without the
session saying so.

## Option A - Docker application

Cloud Foundry pulls the published image and runs it. The push builds nothing:
what reaches the foundation is the exact image that was built, tested and
published.

```bash
scripts/image.sh --push
scripts/deploy-cf.sh --docker
```

```yaml title="deploy/cf/manifest-docker.yml"
--8<-- "deploy/cf/manifest-docker.yml"
```

`((docker_image))` is the only placeholder in that file, because the version
must have exactly one home - `extra.app_version` in `mkdocs.yml`.
`scripts/deploy-cf.sh` reads it there and passes `--var docker_image=...`.

!!! warning "That placeholder is a safety catch"

    `cf push -f deploy/cf/manifest-docker.yml` run by hand fails on the missing
    variable. That is much better than deploying a stale version - or, with no
    image at all, uploading this repository as application source and watching
    Cloud Foundry try to guess what it is.

A private registry needs credentials. They reach `cf` through the environment,
never as an argument, because an argument is visible in the process list:

```bash
export REGISTRY_USER=...
export CF_DOCKER_PASSWORD=...
scripts/deploy-cf.sh --docker
```

## Option B - binary buildpack

No registry needed anywhere.

The binary buildpack compiles nothing. It takes the directory you push, runs
the command you name, and that is all - so the directory has to arrive
complete. `scripts/docs.sh package-cf` assembles it:

```
dist/cf/
|-- mkdocsgo      the pinned release binary, linux/amd64, executable
|-- mkdocs.yml
|-- docs/         Markdown sources - what the MCP index is built from
\-- site/         the built site - what browsers get
```

```bash
scripts/deploy-cf.sh --buildpack   # packages, then pushes
```

```yaml title="deploy/cf/manifest-buildpack.yml"
--8<-- "deploy/cf/manifest-buildpack.yml"
```

Three things that are easy to get wrong:

**No `-http` flag.** The server reads `$PORT`, which Cloud Foundry assigns per
instance. Nothing has to expand a variable at start-up and no port is
hard-coded - which is also why the same binary runs unchanged under Docker and
Kubernetes, where the port is fixed instead.

**The binary must match the cells.** `linux/amd64` for a normal foundation.
`scripts/docs.sh package-cf` downloads it for the target platform rather than
always fetching the linux/amd64 archive, so packaging on a Mac still produces a
package that starts.

**The executable bit has to be set before the push.** A binary that arrives
without it fails at start with a permission error and no other clue.
`scripts/docs.sh package-cf` sets it and then checks it.

### Why not `go_buildpack`

It would compile from source on the foundation: the Go toolchain, the module
cache and network access to a proxy during staging - to produce a binary that a
release already published, reproducibly, with a checksum.

### Why not `staticfile_buildpack`

It is the obvious Cloud Foundry answer for a built MkDocs site, and it works.
It runs nginx over `site/` and serves HTML.

It is also exactly what mkdocsgo replaces: no `/mcp`, no `/healthz`, and the
cache policy and security headers come from an nginx configuration fragment you
maintain per application. If nothing but a browser will ever read this
documentation, it remains a perfectly good choice.

## Sizing and rollout

`memory: 128M` is comfortable. The process holds gzipped copies of the site in
memory - 1.6 MB for a 6.9 MB site - plus the section index and the Go runtime.
64M works for a small site; measure with `cf app mkdocsgo-example` before
trimming.

Two instances for anything with a route people depend on. `--strategy rolling`
(the default in `scripts/deploy-cf.sh`, and the reason cf CLI v7 is the floor)
keeps the old instances serving until the new ones are healthy.

ETags here are content hashes rather than derived from inode and mtime, so two
instances of the same build agree on them. A reader routed to the other
instance does not re-download the site - which is the one thing a two-instance
nginx deployment quietly gets wrong.

## Checking it afterwards

```bash
cf app mkdocsgo-example
curl -sI https://mkdocsgo-example.apps.example.com/healthz
curl -s  https://mkdocsgo-example.apps.example.com/ -o /dev/null -w '%{http_code}\n'
```

The application logs every request unless started with `-no-access-log`:

```bash
cf logs mkdocsgo-example --recent
```
