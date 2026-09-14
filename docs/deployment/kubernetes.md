# Kubernetes

Nothing unusual: a stateless, read-only process with no volumes, no secrets and
nothing to coordinate between replicas.

```bash
kubectl apply -f deploy/k8s/
kubectl rollout status deployment/mkdocsgo-example
```

## Deployment

```yaml title="deploy/k8s/deployment.yaml"
--8<-- "deploy/k8s/deployment.yaml"
```

### Why it can be this locked down

Everything is read once at startup and nothing is ever written. That makes
several settings free rather than brave:

| Setting | Why it costs nothing here |
|---|---|
| `readOnlyRootFilesystem: true` | No file is opened for writing, and there is no scratch directory to grant |
| `runAsNonRoot` + `runAsUser: 65532` | The distroless `nonroot` variant already runs as that uid |
| `capabilities: drop: ["ALL"]` | It binds a high port and does nothing else privileged |
| `allowPrivilegeEscalation: false` | There is no shell and no setuid binary in the image to escalate into |

If a probe ever fails with a read-only filesystem error, something about the
image changed - that is a real signal, not a setting to relax.

### Probes

Probe `/healthz`, never `/`. A 200 from the root proves nothing extra and is a
large response to fetch every few seconds.

Startup is well under a second for a normal documentation set, including
hashing and compressing the site, so the delays do not need to be generous. The
`startupProbe` exists for the exception: a very large site whose first
compression pass takes longer, where a tight `livenessProbe` would otherwise
restart the pod before it finished starting.

### Resources

`64Mi` requested, `128Mi` limit. The process holds the gzipped site in memory -
1.6 MB for a 6.9 MB site - plus the section index and the Go runtime. CPU is
near zero at rest; the `500m` limit is headroom for the startup pass, not for
serving.

## Service

```yaml title="deploy/k8s/service.yaml"
--8<-- "deploy/k8s/service.yaml"
```

**No session affinity.** The MCP endpoint is stateless - no `Mcp-Session-Id`,
which is the sessionless direction of the 2026-07-28 specification - so any
replica can answer any request. Pinning a client to one replica would only make
a rollout worse.

## Ingress

```yaml title="deploy/k8s/ingress.yaml"
--8<-- "deploy/k8s/ingress.yaml"
```

TLS terminates here. mkdocsgo speaks plain HTTP and has no certificate
handling, which is deliberate: in every platform it runs on, something in front
already terminates TLS, and doing it twice buys nothing.

Both halves are one service on one port, so a single `/` rule covers the site,
`/mcp` and `/healthz` alike. Split them only if you want an authentication
policy on `/mcp` that the public site does not have - the 2026-07-28
`Mcp-Method` and `Mcp-Name` headers let a gateway decide without parsing
request bodies.

## Scaling

Replicas are independent and identical. Nothing is shared, so a
HorizontalPodAutoscaler works without further thought:

```bash
kubectl autoscale deployment mkdocsgo-example --min=2 --max=6 --cpu-percent=70
```

In practice documentation rarely needs it. Two replicas are for availability
during a rollout, not for throughput.

## Updating

The image tag is the version. Publish, then roll:

```bash
scripts/image.sh --push
kubectl set image deployment/mkdocsgo-example docs=ghcr.io/kinjelom/mkdocsgo-example:0.2.0
kubectl rollout status deployment/mkdocsgo-example
```

`maxUnavailable: 0` in the strategy means the old replicas keep serving until
the new ones pass their readiness probe.

!!! warning "Do not deploy `:latest`"

    A rollout of `:latest` does something different every time it happens, and
    `kubectl rollout undo` has nothing meaningful to go back to. Pin the
    version - the tag is the only record of what is running.
