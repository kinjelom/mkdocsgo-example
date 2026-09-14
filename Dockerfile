# ---------------------------------------------------------------------------
# mkdocsgo-example - the documentation image
#
# Three stages, and the point of the split is what does NOT reach the last one:
#
#   1. site     python runs `mkdocs build --strict`. The whole documentation
#               toolchain lives and dies in this stage.
#   2. server   the pinned mkdocsgo image, used only as a source of one file.
#   3. runtime  distroless: the binary, the built site, and the Markdown
#               sources the MCP index is built from. No Python, no Node, no
#               shell, no package manager.
#
# The Markdown sources are copied in because the MCP server indexes the
# author's original text, not rendered HTML. They are a fraction of the size
# of the site.
#
# Every ARG below has a matching entry in project.conf, and scripts/image.sh
# passes them in - so the pinned versions have one home, not two. Building this
# file by hand with `docker build .` uses the defaults, which may be older.
# ---------------------------------------------------------------------------

# The same toolbox the scripts use, so the site in this image and the site in
# dist/cf are built by one toolchain rather than two that can drift.
ARG TOOLBOX_IMAGE=ghcr.io/kinjelom/mkdocs-build-toolbox:0.2.0
ARG MKDOCSGO_IMAGE=ghcr.io/kinjelom/mkdocsgo:0.1.1
ARG RUNTIME_IMAGE=gcr.io/distroless/static-debian12:nonroot

# --- 1. Build the site ------------------------------------------------------
# The toolbox already carries MkDocs and every plugin this site pins, so there
# is nothing to install here and no requirements.txt to keep in step with it.
FROM ${TOOLBOX_IMAGE} AS site

WORKDIR /build

COPY mkdocs.yml ./
COPY docs/ ./docs/

# Included into pages with `--8<--` rather than copied into them, so a
# documented manifest cannot drift from the deployed one. `--strict` fails the
# build if one of these is missing, which is the point.
COPY deploy/ ./deploy/
COPY Dockerfile ./

# --strict turns every MkDocs warning - a broken internal link, a page missing
# from the navigation, a snippet that does not resolve - into a build failure,
# so a broken site cannot ship.
RUN mkdocs build --strict --site-dir /site

# --- 2. The server ----------------------------------------------------------
FROM ${MKDOCSGO_IMAGE} AS server

# --- 3. Assemble ------------------------------------------------------------
FROM ${RUNTIME_IMAGE} AS runtime

ARG IMAGE_VERSION=dev

LABEL org.opencontainers.image.title="mkdocsgo-example" \
      org.opencontainers.image.description="Example MkDocs documentation served by mkdocsgo" \
      org.opencontainers.image.source="https://github.com/kinjelom/mkdocsgo-example" \
      org.opencontainers.image.version="${IMAGE_VERSION}"

COPY --from=server /mkdocsgo          /mkdocsgo
COPY --from=site   /site              /project/site
COPY mkdocs.yml                       /project/mkdocs.yml
COPY docs/                            /project/docs/

EXPOSE 8080

# No shell in this image, so the binary probes itself. "self" resolves the
# port from $DOC_PORT or $PORT inside the binary, because HEALTHCHECK in exec
# form has no shell to expand a variable.
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD ["/mkdocsgo", "-healthcheck", "self"]

ENTRYPOINT ["/mkdocsgo"]
CMD ["-mode", "site+mcp", "-project", "/project", "-http", "0.0.0.0:8080"]
