# AWS K3s Observability — Plan

**Goal:** Minimal viable monitoring for the AWS K3s cluster (t3.micro, 1GB RAM).
**Constraint:** No Grafana (too heavy for 1GB RAM). No metrics-server (disabled for memory).

---

## Option 1: Lightweight Prometheus + node-exporter (recommended)

### Components & estimated RAM

| Component | RAM est. | Source |
|-----------|----------|--------|
| Prometheus (--storage.tsdb.min-block-duration=1h, retention=7d) | ~80-120MB | quay.io/prometheus/prometheus |
| node-exporter | ~20MB | DaemonSet, 1 pod |
| kube-state-metrics (optional) | ~30MB | Debian-based |

**Total:** ~130-170MB additional RAM. Current free: ~192MB. Tight but possible.

### Prometheus config

```yaml
global:
  scrape_interval: 60s          # less frequent to save CPU
  evaluation_interval: 60s
  scrape_timeout: 10s

scrape_configs:
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']   # node-exporter on host

  - job_name: 'k3s'
    static_configs:
      - targets: ['localhost:10250']  # kubelet
```

### Storage

```bash
# Prometheus data directory
# Using local-path storage (PVC not available — local-storage disabled)
# Use hostPath: /var/lib/prometheus-data
# Or emptyDir (lost on pod restart — acceptable for trial)
```

### Deployment

```bash
kubectl create ns observability

# node-exporter DaemonSet
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-exporter
  namespace: observability
spec:
  selector:
    matchLabels:
      app: node-exporter
  template:
    metadata:
      labels:
        app: node-exporter
    spec:
      hostNetwork: true
      containers:
      - name: node-exporter
        image: prom/node-exporter:v1.8.2
        args:
          - --path.rootfs=/host
        resources:
          limits:
            memory: 64Mi
            cpu: 50m
          requests:
            memory: 32Mi
            cpu: 25m
        volumeMounts:
          - name: root
            mountPath: /host
            readOnly: true
      volumes:
        - name: root
          hostPath:
            path: /
EOF

# Prometheus Deployment (minimal)
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prometheus
  namespace: observability
spec:
  replicas: 1
  selector:
    matchLabels:
      app: prometheus
  template:
    metadata:
      labels:
        app: prometheus
    spec:
      containers:
      - name: prometheus
        image: prom/prometheus:v2.55.0
        args:
          - --config.file=/etc/prometheus/prometheus.yml
          - --storage.tsdb.path=/prometheus
          - --storage.tsdb.retention.time=7d
          - --storage.tsdb.min-block-duration=1h
          - --web.enable-lifecycle
        resources:
          limits:
            memory: 128Mi
            cpu: 100m
          requests:
            memory: 80Mi
            cpu: 50m
        volumeMounts:
          - name: config
            mountPath: /etc/prometheus
          - name: data
            mountPath: /prometheus
      volumes:
        - name: config
          configMap:
            name: prometheus-config
        - name: data
          emptyDir: {}
EOF
```

---

## Option 2: Host-level monitoring (no K8s overhead)

### Approach
Run `prometheus-node-exporter` and `prometheus` as native systemd services on the EC2 host.
- No K8s pod overhead
- Simpler resource accounting
- Can use `--collector.textfile.directory` for custom metrics

### Trade-offs
- No automatic pod discovery
- Manual configuration for new pods

---

## Option 3: Push to local Grafana (centralized)

### Approach
Configure Prometheus on AWS to remote-write to the local Prometheus/Grafana stack (running on Ubuntu 22.04).

**Pros:** Full Grafana dashboards, no Grafana on AWS.
**Cons:** Network dependency, latency, data transfer costs.
**Security:** Requires TLS + auth on remote-write endpoint.

---

## Decision

Start with **Option 1** (Prometheus + node-exporter in K8s). If memory pressure > threshold, fall back to Option 2 (host-level).

### Go/No-Go check

```bash
# Check available memory BEFORE deploying
free -h
# Must show at least 150Mi available for Prometheus + node-exporter

# Check memory after deploy
ssh ubuntu@13.49.255.149 "curl -s http://localhost:9090/api/v1/status/runtimeinfo | jq ."
```

If available memory < 100Mi after deployment, immediately:
```bash
kubectl delete ns observability
```
and switch to host-level monitoring (Option 2).

---

## References

- [`docs/aws-k3s-setup.md`](aws-k3s-setup.md) — full AWS K3s deployment log
- [`docker/monitoring/`](../docker/monitoring/) — local Prometheus/Grafana stack
- Prometheus minimal config: https://prometheus.io/docs/prometheus/latest/configuration/configuration/
