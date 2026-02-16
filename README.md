# EdgeQuota Helm Chart

> **Developer Preview** — EdgeQuota is under active development and is **not production-ready**. APIs, configuration formats, and behavior may change without notice. If you choose to deploy EdgeQuota in a production environment, you do so at your own risk and accept full responsibility for any consequences. We strongly recommend thorough testing in a staging environment before any production use.

Helm chart for deploying [EdgeQuota](https://github.com/edgequota/edgequota) on Kubernetes.

EdgeQuota is a distributed rate-limiting reverse proxy that sits at the edge of your cluster. It enforces Redis-backed token-bucket rate limits, supports external auth (HTTP/gRPC), and proxies HTTP/1.1, HTTP/2, HTTP/3, gRPC, SSE, and WebSocket traffic on a single port.

## Prerequisites

- Kubernetes 1.28+
- Helm 3.12+ or Helm 4.x
- A Redis instance (single, replication, sentinel, or cluster). Redis deployment is **out of scope** for this chart.

Optional:
- [cert-manager](https://cert-manager.io/) for automated TLS certificate management
- [prometheus-operator](https://github.com/prometheus-operator/kube-prometheus) (kube-prometheus-stack) for ServiceMonitor support

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
                  ┌──────────────────────────────────────────┐
                  │              EdgeQuota Pod                │
Internet ──▶ Ingress ──▶ :8080 (proxy) ──▶ Backend Service   │
                  │       :9090 (admin/metrics/health)       │
                  │              │                            │
                  │              ▼                            │
                  │         Redis (external)                  │
                  └──────────────────────────────────────────┘
```

**Request flow:** Auth (optional) → Rate Limit → Reverse Proxy → Backend

## Example Values

This chart ships with two example value files:

| File | Purpose |
|---|---|
| [`values-minimal.yaml`](values-minimal.yaml) | Bare minimum for dev/test. Single replica, single Redis, inline password. |
| [`values-production.yaml`](values-production.yaml) | Production-ready. HPA (3-15 replicas), Redis Sentinel, PDB, NetworkPolicy, Ingress with cert-manager TLS, ServiceMonitor, topology spread, pod anti-affinity. |

## What Gets Deployed

Resources are conditionally rendered based on your values:

| Resource | Condition | Default |
|---|---|---|
| ServiceAccount | `serviceAccount.create` | enabled |
| Role + RoleBinding | `rbac.create` | enabled |
| ConfigMap | always | always |
| Secret | `secrets.create` | disabled |
| Deployment | always | always |
| Service | always | always |
| HorizontalPodAutoscaler | `autoscaling.enabled` | disabled |
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
| `edgequota.backend.url` | Backend URL (required unless external rate limit mode) | `""` |
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

#### Rate Limiting

| Parameter | Description | Default |
|---|---|---|
| `edgequota.rateLimit.average` | Requests per period (0 = disabled) | `0` |
| `edgequota.rateLimit.burst` | Burst capacity | `1` |
| `edgequota.rateLimit.period` | Time period | `1s` |
| `edgequota.rateLimit.failurePolicy` | `passThrough`, `failClosed`, `inMemoryFallback` | `passThrough` |
| `edgequota.rateLimit.keyStrategy.type` | `clientIP`, `header`, `composite` | `clientIP` |

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
```

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

### Monitoring

Prometheus annotations are enabled by default. For prometheus-operator:

```yaml
metrics:
  serviceMonitor:
    enabled: true
    interval: "15s"
```

### Health Endpoints

All served on the admin port (default `:9090`):

| Endpoint | Probe | Description |
|---|---|---|
| `GET /startz` | Startup | 200 when init complete, 503 during startup |
| `GET /healthz` | Liveness | Always 200 while process runs |
| `GET /readyz` | Readiness | 200 when ready, 503 during startup/shutdown |
| `GET /metrics` | Prometheus | Metrics in Prometheus text format |

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
