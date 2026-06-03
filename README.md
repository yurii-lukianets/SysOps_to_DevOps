# SysOps to DevOps

Personal DevOps learning path built from scratch — from Windows workstation to production-grade infrastructure spanning two environments: a local K3s cluster (Ubuntu 22.04) and an AWS K3s cluster (EC2 t3.micro, Free Tier).

## Live

| Endpoint | Description | Platform |
|----------|-------------|----------|
| [https://ai-devops.pp.ua](https://ai-devops.pp.ua) | Portfolio — TLS, Cloudflare WAF | AWS K3s |
| [https://llm.ai-devops.pp.ua](https://llm.ai-devops.pp.ua) | Self-hosted LLM API — Qwen3-35B | Local K3s (RTX 3050) |

## Stack

| Category | Technology | Environment |
|----------|------------|-------------|
| Container Orchestration | K3s v1.35 on Ubuntu 22.04 | Local + AWS |
| GitOps / CD | ArgoCD v3.4.2 | Local |
| Ingress | Traefik (built-in K3s) | Both |
| TLS | cert-manager + Let's Encrypt | Both |
| CI/CD | GitHub Actions + self-hosted runner | Local |
| IaC | Terraform + Ansible | Both |
| Monitoring | Prometheus + Grafana + node-exporter | Local |
| Object Storage | MinIO (S3-compatible) | Local |
| Local LLM | Qwen3-35B via llama.cpp (RTX 3050) | Local (Windows) |
| LLM API | FastAPI (Python) + Docker | Local |
| Container Registry | GHCR | Both |
| Security | Cloudflare WAF + iptables + CrowdSec | Both |
| Traffic Analytics | GoAccess + GeoIP | Local |
| Cloud Provider | AWS (eu-north-1, Free Tier) | AWS |
| Terraform State | S3 + DynamoDB locks | AWS |
| AI Dev Tools | Claude Code CLI + Continue.dev | Windows |

---

## Progress

### Step 1–4: Foundation
- [x] Windows workstation — Git, VS Code, SSH
- [x] GitHub repository structure
- [x] Docker infrastructure on Ubuntu 22.04 (Portainer, Docker Compose)
- [x] Monitoring stack — Prometheus + Grafana + node-exporter
  → [`docker/monitoring/`](docker/monitoring/)

### Step 5–7: Automation & IaC
- [x] CI/CD — GitHub Actions + self-hosted runner → [`github/workflows/`](.github/workflows/)
- [x] Ansible IaC — roles: docker, portainer, monitoring → [`ansible/`](ansible/)
- [x] Terraform — MinIO S3 remote state backend → [`terraform/`](terraform/)

### Step 8–9: Kubernetes
- [x] K3s v1.35 on Ubuntu 22.04
- [x] ArgoCD GitOps — auto-sync, self-heal → [`k8s/`](k8s/)
  → Tested: `git push` → auto scale 1→2 replicas

### Step 10: Portfolio site with HTTPS — Variant A
- [x] Static site via ArgoCD — [`k8s/portfolio/`](k8s/portfolio/)
- [x] Traefik + cert-manager + Let's Encrypt (TLS 1.3)
- [x] Domain: [ai-devops.pp.ua](https://ai-devops.pp.ua)

### Step 11: Self-hosted LLM API — Variant B
- [x] FastAPI proxy → Qwen3-35B via llama.cpp → [`llm-api/`](llm-api/)
- [x] GitHub Actions → GHCR → ArgoCD → K3s
- [x] API Key auth + OpenAI-compatible endpoint
- [x] Test suite 6/6 → [`llm-api/tests/test_api.sh`](llm-api/tests/test_api.sh)
- [x] Docs: [`llm-api/docs/test-results.md`](llm-api/docs/test-results.md)

### Step 12: Full observability — Variant C
- [x] Prometheus metrics in FastAPI (requests, tokens, duration, tok/s)
- [x] llama.cpp native `/metrics` scraped by Prometheus
- [x] Grafana dashboard 10 panels → [`docker/monitoring/grafana-llm-dashboard.json`](docker/monitoring/grafana-llm-dashboard.json)
- [x] LLM benchmark results → [`llm-api/docs/benchmark-results.md`](llm-api/docs/benchmark-results.md)

### Step 13: Production security
- [x] Cloudflare WAF + proxy (real visitor IPs, DDoS protection)
- [x] iptables — only Cloudflare IPs on 80/443, all internal ports closed
- [x] CrowdSec — 780 scenarios, auto-ban via firewall bouncer
- [x] GoAccess traffic analytics + GeoIP dashboard
- [x] Security docs → [`docs/security/setup.md`](docs/security/setup.md)

### Step 14: AWS K3s deployment (Free Tier)
- [x] Terraform EC2 + SG + EIP + key pair → [`terraform/aws/`](terraform/aws/)
- [x] K3s v1.35.5 on t3.micro (1GB RAM + 4GB swap)
- [x] kubectl from Windows (direct + SSH tunnel)
- [x] cert-manager + Let's Encrypt TLS
- [x] Security Group locked to Cloudflare IPs (80/443) + my IP (22/6443)
- [x] Resource limits + probes on all pods
- [x] Terraform state migrated to S3 + DynamoDB locking
- [x] SQLite automated backup (daily @ midnight, 7-day retention)
- [x] OOM recovery: 4GB swap, disabled metrics-server/local-storage, kubelet-arg
- [x] HTTPS live: [https://ai-devops.pp.ua](https://ai-devops.pp.ua) (Cloudflare proxied)
- [ ] **Observability on AWS** — lightweight Prometheus/node-exporter
- [ ] Portfolio UX improvements (health endpoint, status)

## Next Steps — Observability on AWS

The AWS K3s runs on t3.micro (1GB RAM), which is too tight for the full Grafana stack. The plan is a **minimal viable observability** setup:

### Priority 1: Node-level metrics
Deploy a single **node-exporter** DaemonSet + lightweight Prometheus scraping itself.
- No Grafana (too heavy for 1GB RAM)
- Prometheus in `--storage.tsdb.retention.time=7d` minimal mode
- Alerts via `amtool` or simple webhook

### Priority 2: K3s control-plane metrics
Scrape K3s `/metrics` endpoints (apiserver, controller-manager, scheduler, kubelet).
- Already exposed by default
- Prometheus additional scrape targets

### Priority 3: Application metrics
Add a `/metrics` endpoint to portfolio (nginx → stub_status + custom).
- Track requests, errors, latency

### Priority 4: Verify vs. local stack
Compare resource cost vs. benefit — if Prometheus alone is too heavy, consider:
- Host-level `collectd` + CloudWatch
- Push to local Grafana via remote write (centralized dashboard)
- Or skip AWS observability and rely on Cloudflare analytics + AWS CloudWatch

Details → [`docs/observability-aws.md`](docs/observability-aws.md) (planned)

---

## LLM Benchmarks (RTX 3050, 8GB VRAM)

Model: `Qwen3.6-35B-A3B-MXFP4_MOE.gguf` — 35B params, MXFP4 MoE

| Metric | Value | Notes |
|--------|-------|-------|
| Generation speed | 28–34 tok/s | ncmoe=32 optimal |
| Prompt processing | 411 tok/s | ncmoe=32, ub=1024 |
| Avg request duration | 2.89–3.34s | via API |
| VRAM usage | 7694 / 8192 MiB | 94% |
| Context window | 32768 tokens | |

Full parameter sweep → [`llm-api/docs/benchmark-results.md`](llm-api/docs/benchmark-results.md)

**Optimal launch:**
```powershell
.\llama-server.exe -m "Qwen3.6-35B-A3B-MXFP4_MOE.gguf" -fa 1 -ngl 99 -ncmoe 32 -ub 1024 -b 1024 -t 12 -ctk q8_0 -ctv q8_0 --jinja --host 0.0.0.0 --port 8080 --metrics
```

---

## Security Stack

```
Internet → Cloudflare WAF → iptables → Traefik → CrowdSec → Services
```

| Layer | Tool | Function |
|-------|------|----------|
| Edge | Cloudflare Free | WAF, DDoS, GeoIP, real IP headers |
| Network | iptables | Only CF IPs on 80/443 |
| Behavioral | CrowdSec | 780 scenarios, community blocklist |
| Enforcement | crowdsec-firewall-bouncer | Auto-ban via iptables |
| Analytics | GoAccess + GeoIP | Traffic dashboard, bot detection |

Bans detected in first hour: CVE-2017-9841, ThinkPHP RCE, WordPress scan, HTTP probing

Details → [`docs/security/setup.md`](docs/security/setup.md)

---

## API Usage

```bash
# Health (public)
curl https://llm.ai-devops.pp.ua/health

# Chat (API key required)
curl -X POST https://llm.ai-devops.pp.ua/v1/chat \
  -H "Content-Type: application/json" \
  -H "X-API-Key: YOUR_KEY" \
  -d '{"message": "What is GitOps?", "max_tokens": 100}'

# Run test suite
export API_KEY=your-key
bash llm-api/tests/test_api.sh https://llm.ai-devops.pp.ua
# Expected: 6/6 passed
```

---

## Startup Checklist

Full checklist with verification commands → [`docs/CHECKLIST.md`](docs/CHECKLIST.md)

---

## Key Achievements

- **End-to-end GitOps**: `git push` → Actions → GHCR → ArgoCD → K3s → live in <2 min
- **Self-hosted AI**: 35B LLM on consumer GPU with production API and benchmarks
- **Full observability**: Prometheus + Grafana with real measured performance data
- **Production security**: 4-layer protection, auto-banning attackers from first hour
- **Verified performance**: 34 tok/s generation — measured, not estimated## Model Architecture
- **MoE (Mixture of Experts)**: 35B total params, but only ~3B active per token
- **Quantization**: MXFP4 MOE — optimized for MoE architecture
- **Why it fits**: Active params fit in 8GB VRAM, sparse activation pattern