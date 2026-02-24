# EdgeQuota Helm Chart

> **Developer Preview** — EdgeQuota is under active development and is **not production-ready**. APIs, configuration formats, and behavior may change without notice. If you choose to deploy EdgeQuota in a production environment, you do so at your own risk and accept full responsibility for any consequences. We strongly recommend thorough testing in a staging environment before any production use.

Helm chart for deploying [EdgeQuota](https://github.com/edgequota/edgequota) on Kubernetes.

EdgeQuota is a distributed rate-limiting reverse proxy and CDN-style response cache that sits at the edge of your cluster. It enforces Redis-backed token-bucket rate limits, supports external auth and rate-limit services (HTTP/gRPC), caches upstream responses honoring `Cache-Control` headers, and proxies HTTP/1.1, HTTP/2, HTTP/3, gRPC, SSE, and WebSocket traffic on a single port.

## Prerequisites

- Kubernetes 1.28+
- Helm 3.12+ or Helm 4.x
- A Redis instance (single, replication, sentinel, or cluster). Redis deployment is **out of scope** for this chart.

Optional:
- [cert-manager](https://cert-manager.io/) for automated TLS certificate management
- [prometheus-operator](https://github.com/prometheus-operator/kube-prometheus) (kube-prometheus-stack) for ServiceMonitor support
- [Vertical Pod Autoscaler](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler) for VPA resource recommendations

## Quick Start

### Add the Helm repository

```bash
helm repo add edgequota https://edgequota.github.io/edgequota-helm
helm repo update
```

### Install with minimal values

```bash
helm install edgequota edgequota/edgequota -f values-minimal.yaml
```

### Install with production values

```bash
helm install edgequota edgequota/edgequota \
  -n edgequota --create-namespace \
  -f values-production.yaml
```

### Install from source

```bash
git clone https://github.com/edgequota/edgequota-helm.git
cd edgequota-helm
helm install edgequota . -f values-minimal.yaml
```

## Architecture

```
                  ┌─────────────────────────────────────────────────────┐
                  │                   EdgeQuota Pod                      │
Internet ──▶ Ingress ──▶ :80/443 (proxy svc) ──▶ :8080 ──▶ Backend
                  │                                                      │
                  │    :9090 (admin svc, ClusterIP only)                 │
                  │         │                                            │
                  │         ▼                                            │
                  │    Redis (rate limits, ext-RL cache, response cache) │
                  └─────────────────────────────────────────────────────┘
```

The chart creates two services:
- **Proxy service** (`<release>-edgequota`) — port 80 (no TLS) or 443 (TLS), targeting container port 8080. Type is configurable (ClusterIP, NodePort, LoadBalancer).
- **Admin service** (`<release>-edgequota-admin`) — always ClusterIP on port 9090. Serves health probes, readiness checks, Prometheus metrics, and cache invalidation APIs.

**Request flow:** Auth (optional) → Response Cache check → Rate Limit → Reverse Proxy → Backend → Response Cache store

## Example Values

This chart ships with two example value files:

| File | Purpose |
|---|---|
| [`values-minimal.yaml`](values-minimal.yaml) | Bare minimum for dev/test. Single replica, single Redis, inline password. |
| [`values-production.yaml`](values-production.yaml) | Production-ready. HPA (3-15 replicas), VPA (Off mode for recommendations), Redis Sentinel, PDB, NetworkPolicy, Ingress with cert-manager TLS, ServiceMonitor, topology spread, pod anti-affinity. |

## What Gets Deployed

Resources are conditionally rendered based on your values:

| Resource | Condition | Default |
|---|---|---|
| ServiceAccount | `serviceAccount.create` | enabled |
| Role + RoleBinding | `rbac.create` | enabled |
| ConfigMap | always | always |
| Secret | `secrets.create` | disabled |
| Deployment | always | always |
| Service (proxy) | always | always |
| Service (admin) | always | always |
| HorizontalPodAutoscaler | `autoscaling.enabled` | disabled |
| VerticalPodAutoscaler | `verticalPodAutoscaler.enabled` | disabled |
| PodDisruptionBudget | `podDisruptionBudget.enabled` | disabled |
| Ingress | `ingress.enabled` | disabled |
| Certificate (cert-manager) | `certificate.enabled` | disabled |
| ServiceMonitor | `metrics.serviceMonitor.enabled` | disabled |
| NetworkPolicy | `networkPolicy.enabled` | disabled |

## Configuration

All configuration is documented inline in [`values.yaml`](values.yaml). Below is a summary of the major sections.

### Image

| Parameter | Description | Default |
|---|---|---|
| `image.registry` | Container image registry | `""` |
| `image.repository` | Container image repository | `ghcr.io/shoro-io/edgequota` |
| `image.tag` | Image tag (defaults to `appVersion`) | `""` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |

### EdgeQuota Application

These values are rendered into the ConfigMap that EdgeQuota reads as `config.yaml`.

#### Server (proxy)

| Parameter | Description | Default |
|---|---|---|
| `edgequota.server.port` | Proxy listen port | `8080` |
| `edgequota.server.readTimeout` | HTTP read timeout | `30s` |
| `edgequota.server.writeTimeout` | HTTP write timeout | `30s` |
| `edgequota.server.idleTimeout` | Connection idle timeout | `120s` |
| `edgequota.server.drainTimeout` | Graceful shutdown drain | `30s` |
| `edgequota.server.tls.enabled` | Enable TLS on the proxy | `false` |
| `edgequota.server.tls.minVersion` | Minimum TLS version | `""` |
| `edgequota.server.tls.http3Enabled` | Enable HTTP/3 (QUIC) | `false` |

#### Backend

| Parameter | Description | Default |
|---|---|---|
| `edgequota.rateLimit.static.backendUrl` | Backend URL (required unless external rate limit mode) | `""` |
| `edgequota.backend.timeout` | Request timeout | `30s` |
| `edgequota.backend.maxIdleConns` | Max idle connections | `100` |
| `edgequota.backend.idleConnTimeout` | Idle connection timeout | `90s` |

#### Redis

| Parameter | Description | Default |
|---|---|---|
| `edgequota.redis.endpoints` | Redis endpoint(s) | `localhost:6379` |
| `edgequota.redis.mode` | `single`, `replication`, `sentinel`, `cluster` | `single` |
| `edgequota.redis.masterName` | Sentinel master name | `""` |
| `edgequota.redis.poolSize` | Connection pool size | `10` |
| `edgequota.redis.tls.enabled` | Enable TLS for Redis | `false` |

#### CDN-style Response Cache

When enabled, EdgeQuota caches upstream HTTP responses in Redis and serves them on subsequent requests — exactly like a CDN. Backends opt in by returning standard `Cache-Control` headers:

```
Cache-Control: public, max-age=300      # cache for 5 minutes
Cache-Control: no-store                 # never cache this response
Surrogate-Key: product-123 category-x  # tag-based invalidation
```

Only `GET` requests and `200`/`301` responses are cached. WebSocket, gRPC, SSE, and non-GET requests always bypass the cache.

| Parameter | Description | Default |
|---|---|---|
| `edgequota.cache.enabled` | Enable CDN-style response cache | `false` |
| `edgequota.cache.maxBodySize` | Max response body size to cache | `1MB` |
| `edgequota.responseCacheRedis.endpoints` | Dedicated Redis for response cache (empty = share main Redis) | `[]` |
| `edgequota.responseCacheRedis.mode` | Redis mode for response cache Redis | `single` |
| `edgequota.responseCacheRedis.poolSize` | Connection pool size | `10` |

**Redis fallback chain:** `responseCacheRedis` → `cacheRedis` → main `redis`.

**Cache invalidation** is available via the admin API (port 9090):

```bash
# Purge a single URL
curl -X POST http://admin:9090/v1/cache/purge \
  -H 'Content-Type: application/json' \
  -d '{"url":"/api/products","method":"GET"}'

# Purge all entries tagged with a Surrogate-Key
curl -X POST http://admin:9090/v1/cache/purge/tags \
  -H 'Content-Type: application/json' \
  -d '{"tags":["product-123","category-shoes"]}'
```

Returns `204 No Content` on success, `404` if the entry was not found.

**Minimal example:**

```yaml
edgequota:
  cache:
    enabled: true
    maxBodySize: "5MB"
```

**With a dedicated cache Redis:**

```yaml
edgequota:
  cache:
    enabled: true
    maxBodySize: "10MB"
  responseCacheRedis:
    endpoints:
      - "cdn-redis-primary:6379"
      - "cdn-redis-replica:6379"
    mode: "replication"
    poolSize: 50
```

#### Rate Limiting

EdgeQuota has two rate-limiting modes. **Static** (default): fixed token-bucket limits enforced locally. **External**: an external service provides per-request quotas; the `static` block is ignored and `external.fallback` is required as a safety net.

| Parameter | Description | Default |
|---|---|---|
| `edgequota.rateLimit.failurePolicy` | Redis failure policy: `passThrough`, `failClosed`, `inMemoryFallback` | `passThrough` |
| **Static** (used when external RL is disabled) | | |
| `edgequota.rateLimit.static.average` | Requests per period (0 = disabled) | `0` |
| `edgequota.rateLimit.static.burst` | Burst capacity | `1` |
| `edgequota.rateLimit.static.period` | Time period | `1s` |
| `edgequota.rateLimit.static.keyStrategy.type` | `clientIP`, `header`, `composite`, `global` | `clientIP` |
| `edgequota.rateLimit.static.keyStrategy.headerName` | Header to extract key from (required for `header`/`composite`) | `""` |
| `edgequota.rateLimit.static.keyStrategy.globalKey` | Fixed key for `global` strategy | `""` |
| **External** (delegates quota to external service) | | |
| `edgequota.rateLimit.external.enabled` | Enable external rate-limit service | `false` |
| `edgequota.rateLimit.external.timeout` | Request timeout | `5s` |
| `edgequota.rateLimit.external.http.url` | HTTP endpoint URL | `""` |
| `edgequota.rateLimit.external.grpc.address` | gRPC endpoint address | `""` |
| **External Fallback** (required when `external.enabled` is true) | | |
| `edgequota.rateLimit.external.fallback.average` | Fallback requests per period (must be > 0) | `0` |
| `edgequota.rateLimit.external.fallback.burst` | Fallback burst capacity | `1` |
| `edgequota.rateLimit.external.fallback.period` | Fallback time period | `1s` |
| `edgequota.rateLimit.external.fallback.keyStrategy.type` | Fallback key strategy: `clientIP`, `header`, `composite`, `global` | `global` |
| `edgequota.rateLimit.external.fallback.keyStrategy.globalKey` | Fixed key for `global` fallback | `fallback` |

#### Auth, Logging, Tracing

| Parameter | Description | Default |
|---|---|---|
| `edgequota.auth.enabled` | Enable external auth | `false` |
| `edgequota.logging.level` | Log level | `info` |
| `edgequota.logging.format` | Log format (`json`, `text`) | `json` |
| `edgequota.tracing.enabled` | Enable OpenTelemetry tracing | `false` |

### Security Hardening

The chart applies security best practices by default:

- **Non-root user** (UID/GID 65534) matching the distroless base image
- **Read-only root filesystem**
- **All capabilities dropped**
- **Seccomp profile** set to `RuntimeDefault`
- **Service account token** not automounted
- **RBAC** with minimal permissions (read own ConfigMap only)

### Secrets Management

Two approaches for Redis credentials:

**Option A: Chart-managed Secret**
```yaml
secrets:
  create: true
  redisPassword: "my-password"
```

**Option B: Existing Secret (recommended for production)**
```yaml
secrets:
  create: false
  existingSecret: "my-redis-secret"
  existingSecretMappings:
    - envVar: EDGEQUOTA_REDIS_PASSWORD
      key: redis-password
    # Uncomment when using a dedicated cache Redis:
    # - envVar: EDGEQUOTA_CACHE_REDIS_PASSWORD
    #   key: cache-redis-password
    # Uncomment when using a dedicated response cache Redis:
    # - envVar: EDGEQUOTA_RESPONSE_CACHE_REDIS_PASSWORD
    #   key: response-cache-redis-password
```

Available secret environment variables:

| Env Var | Secret key (chart-managed) | Purpose |
|---|---|---|
| `EDGEQUOTA_REDIS_PASSWORD` | `redis-password` | Main Redis |
| `EDGEQUOTA_REDIS_USERNAME` | `redis-username` | Main Redis |
| `EDGEQUOTA_REDIS_SENTINEL_PASSWORD` | `redis-sentinel-password` | Main Redis Sentinel |
| `EDGEQUOTA_CACHE_REDIS_PASSWORD` | `cache-redis-password` | External RL cache Redis |
| `EDGEQUOTA_CACHE_REDIS_SENTINEL_PASSWORD` | `cache-redis-sentinel-password` | External RL cache Redis Sentinel |
| `EDGEQUOTA_RESPONSE_CACHE_REDIS_PASSWORD` | `response-cache-redis-password` | Response cache Redis |
| `EDGEQUOTA_RESPONSE_CACHE_REDIS_SENTINEL_PASSWORD` | `response-cache-redis-sentinel-password` | Response cache Redis Sentinel |

### Ingress with cert-manager

```yaml
ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  hosts:
    - host: edgequota.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: edgequota-tls
      hosts:
        - edgequota.example.com
```

### Pod-level TLS with cert-manager

For end-to-end TLS (e.g., when exposing EdgeQuota directly as a LoadBalancer):

```yaml
certificate:
  enabled: true
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - edgequota.example.com

edgequota:
  server:
    tls:
      enabled: true
```

### Autoscaling

#### Horizontal Pod Autoscaler (HPA)

```yaml
autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 15
  targetCPUUtilizationPercentage: 70
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
```

#### Vertical Pod Autoscaler (VPA)

Requires the [VPA CRD](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler) (`autoscaling.k8s.io/v1`) to be installed in the cluster.

| Parameter | Description | Default |
|---|---|---|
| `verticalPodAutoscaler.enabled` | Enable VPA | `false` |
| `verticalPodAutoscaler.updateMode` | `Auto`, `Recreate`, or `Off` | `Auto` |
| `verticalPodAutoscaler.containerPolicies` | Per-container min/max resource boundaries | see `values.yaml` |

When running **both HPA and VPA**, set `updateMode: "Off"` so VPA only provides recommendations without mutating pods (HPA handles scaling):

```yaml
verticalPodAutoscaler:
  enabled: true
  updateMode: "Off"
  containerPolicies:
    - containerName: "*"
      minAllowed:
        cpu: 100m
        memory: 64Mi
      maxAllowed:
        cpu: "4"
        memory: 4Gi
      controlledResources: ["cpu", "memory"]
```

### Monitoring

Prometheus annotations are enabled by default. For prometheus-operator:

```yaml
metrics:
  serviceMonitor:
    enabled: true
    interval: "15s"
```

### Admin API Endpoints

All served on the admin port (default `:9090`):

| Endpoint | Method | Probe/Purpose | Description |
|---|---|---|---|
| `/startz` | GET | Startup | `200` when init complete, `503` during startup |
| `/healthz` | GET | Liveness | Always `200` while process runs |
| `/readyz` | GET | Readiness | `200` when ready, `503` during startup/shutdown |
| `/metrics` | GET | Prometheus | Metrics in Prometheus text format |
| `/v1/config` | GET | Ops | Redacted runtime configuration dump |
| `/v1/cache/purge` | POST | Cache ops | Purge a cached response by URL/method |
| `/v1/cache/purge/tags` | POST | Cache ops | Purge cached responses by `Surrogate-Key` tags |

### Escape Hatches

For anything not covered by the chart values:

| Parameter | Description |
|---|---|
| `extraArgs` | Extra CLI arguments to the edgequota binary |
| `extraEnv` | Extra environment variables |
| `extraEnvFrom` | Extra envFrom sources |
| `extraVolumeMounts` | Extra volume mounts |
| `extraVolumes` | Extra volumes |
| `initContainers` | Init containers |
| `sidecars` | Sidecar containers |
| `edgequota.extraConfig` | Extra entries in the ConfigMap |

## Upgrading

### Version compatibility

| Chart version | EdgeQuota version | Kubernetes | Helm |
|---|---|---|---|
| 0.1.x | 0.1.x | 1.28+ | 3.12+ / 4.x |

### Upgrade procedure

```bash
helm repo update
helm upgrade edgequota edgequota/edgequota -f your-values.yaml
```

The chart includes checksum annotations on the Deployment, so any change to the ConfigMap or Secret triggers a rolling restart automatically.

## Development

### Lint

```bash
helm lint .
helm lint . --strict -f values-minimal.yaml
helm lint . --strict -f values-production.yaml
```

### Template

```bash
helm template test . --namespace test
helm template test . --namespace test -f values-production.yaml
```

### Test in a local cluster

```bash
kind create cluster
helm install redis bitnami/redis --set auth.password=test --set architecture=standalone --wait
helm install edgequota . -f values-minimal.yaml \
  --set edgequota.redis.endpoints="redis-master:6379" \
  --set secrets.redisPassword="test"
```

## CI/CD

The chart includes a comprehensive GitHub Actions CI pipeline (`.github/workflows/ci.yml`) that runs on every push and PR:

- **Lint** - `helm lint` with default, minimal, and production values (including strict mode)
- **Validate** - kubeconform against Kubernetes 1.28-1.31
- **Template** - Render and verify all value combinations produce valid resources
- **Chart Testing** - `ct lint` + install test in a kind cluster with a real Redis
- **Security** - Trivy config scan + Checkov for misconfigurations
- **Docs** - Validates that all top-level values keys are documented

On tag push (`v*`), after all checks pass, the chart is packaged and published to the `docs/` directory on `main` for GitHub Pages serving.

## Links

- [EdgeQuota source code](https://github.com/edgequota/edgequota)
- [EdgeQuota documentation](https://github.com/edgequota/edgequota#readme)
- [This Helm chart repository](https://github.com/edgequota/edgequota-helm)

## License

This chart is licensed under the [Apache License 2.0](LICENSE).
