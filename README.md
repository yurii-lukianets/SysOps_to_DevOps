# SysOps to DevOps

Personal DevOps learning path built from scratch — from Windows workstation to production Kubernetes with self-hosted LLM inference, full GitOps pipeline, and real-time observability.

## Live Infrastructure

| Endpoint | Description |
|----------|-------------|
| [https://ai-devops.pp.ua](https://ai-devops.pp.ua) | Portfolio site — deployed via ArgoCD GitOps |
| [https://llm.ai-devops.pp.ua](https://llm.ai-devops.pp.ua) | Self-hosted LLM API — Qwen3-35B via llama.cpp |

> Both services run on self-hosted K3s cluster with automated TLS via Let's Encrypt

## Stack

| Category | Technology |
|----------|------------|
| Container Orchestration | K3s v1.35 on Ubuntu 22.04 |
| GitOps / CD | ArgoCD v3.4.2 |
| Ingress | Traefik (built-in K3s) |
| TLS | cert-manager + Let's Encrypt |
| CI/CD | GitHub Actions + self-hosted runner |
| IaC | Ansible + Terraform |
| Monitoring | Prometheus + Grafana + node-exporter |
| Object Storage | MinIO (S3-compatible, Terraform backend) |
| Local LLM | Qwen3-35B via llama.cpp (RTX 3050, 8GB VRAM) |
| LLM API | FastAPI (Python) + Docker |
| Container Registry | GitHub Container Registry (GHCR) |
| AI Dev Tools | Claude Code CLI + Continue.dev (VS Code) |

## Progress

- [x] **Step 1: Windows workstation setup**
  - Git, VS Code, WSL2, PowerShell tools
  - SSH key generation and GitHub configuration

- [x] **Step 2: GitHub repository**
  - Repository structure and branching strategy
  - README-driven development approach

- [x] **Step 3: Docker infrastructure on Ubuntu 22.04**
  - Server: Intel Core2 Quad 2.4GHz, 4GB RAM, 98GB disk
  - Portainer CE for container management
  - Docker Compose for service orchestration

- [x] **Step 4: Monitoring stack (Docker)**
  - Prometheus — metrics collection (port 9091)
  - Grafana — dashboards with Node Exporter Full (ID 1860)
  - node-exporter — host metrics (CPU, RAM, disk, network)
  - All services managed via Docker Compose

- [x] **Step 5: CI/CD pipeline**
  - GitHub Actions: validate.yml + deploy.yml
  - Self-hosted runner on Ubuntu server
  - Auto-deploy on push to docker/**

- [x] **Step 6: Infrastructure as Code (Ansible)**
  - Roles: docker, portainer, monitoring
  - Idempotent playbook: ansible-playbook ansible/site.yml
  - Local connection (ansible_connection=local)

- [x] **Step 7: Terraform IaC**
  - Docker provider (kreuzwerker/docker v3.9)
  - Remote state: MinIO S3-compatible backend
  - Full lifecycle: init, plan, apply, destroy

- [x] **Step 8: K3s (Lightweight Kubernetes)**
  - K3s v1.35.4 on Ubuntu 22.04
  - Built-in: Traefik ingress, CoreDNS, Metrics Server, Helm
  - Remote kubectl access from Windows
  - First deployment: Nginx via kubectl manifest

- [x] **Step 9: ArgoCD GitOps**
  - ArgoCD v3.4.2 in K3s (namespace: argocd)
  - Auto-sync + Self-heal enabled
  - Tested: git push → automatic scale 1→2 replicas

- [x] **Step 10: Portfolio site with HTTPS — Variant A**
  - Static site deployed via ArgoCD from k8s/portfolio/
  - Traefik ingress + cert-manager + Let's Encrypt (TLS 1.3)
  - Domain: ai-devops.pp.ua
  - Full GitOps: git push → ArgoCD sync → live update

- [x] **Step 11: Self-hosted LLM API — Variant B**
  - FastAPI proxy to local Qwen3-35B (llama.cpp, CUDA)
  - Docker image built via GitHub Actions → pushed to GHCR
  - Deployed to K3s via ArgoCD auto-sync
  - HTTPS endpoint: llm.ai-devops.pp.ua
  - API Key authentication (X-API-Key header)
  - OpenAI-compatible API (/v1/chat/completions)
  - Test suite: 6/6 tests passing

- [x] **Step 12: Full GitOps observability stack — Variant C**
  - Prometheus metrics in FastAPI: requests, tokens, duration, tok/s
  - llama.cpp native /metrics endpoint scraped by Prometheus
  - Grafana dashboard with 10 panels — live LLM performance data
  - NodePort 30800 for internal Prometheus scraping
  - Rolling updates on every git push via GitHub Actions → ArgoCD

## LLM Performance Benchmarks (RTX 3050, 8GB VRAM)

Model: Qwen3.6-35B-A3B-MXFP4_MOE.gguf — 35B parameters, MXFP4 MoE quantization

| Metric | Value |
|--------|-------|
| Generation speed | 28–30 tok/s |
| Prompt processing | 18–50 tok/s |
| Avg request duration | 2.89–3.34s |
| VRAM usage | 7694 / 8192 MiB (94%) |
| Context window | 32768 tokens |
| Host RAM under load | ~65% |
| Host CPU under load | ~15–20% |

> Benchmarks collected via live Prometheus metrics + Grafana dashboard during real API requests

## Grafana Dashboard — Live Metrics

10 panels tracking real-time LLM inference:
- Total requests counter + tokens generated
- Tokens/sec over time (generation + prompt)
- llama.cpp native metrics (predicted/prompt throughput)
- Active request slots (processing, deferred, busy)
- Host CPU & RAM during inference
- Request rate & average duration

## API Usage

```bash
# Health (public)
curl https://llm.ai-devops.pp.ua/health

# Chat
curl -X POST https://llm.ai-devops.pp.ua/v1/chat \
  -H "Content-Type: application/json" \
  -H "X-API-Key: YOUR_KEY" \
  -d '{"message": "What is GitOps?", "max_tokens": 100}'

# OpenAI-compatible
curl -X POST https://llm.ai-devops.pp.ua/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "X-API-Key: YOUR_KEY" \
  -d '{"model":"qwen3","messages":[{"role":"user","content":"Hello"}],"max_tokens":50}'

# Run test suite
export API_KEY=your-key
bash llm-api/tests/test_api.sh https://llm.ai-devops.pp.ua
```

## Infrastructure Map

```
Windows (windows-host)
  └── llama-server (Qwen3-35B, RTX 3050, port 8080)
  └── VS Code + Continue.dev → local LLM autocomplete

Ubuntu 22.04 (ubuntu-server)
  ├── Docker containers
  │   ├── Portainer     :9000
  │   ├── Prometheus    :9091  ← scrapes llama-server + llm-api + node
  │   ├── Grafana       :3000  ← LLM dashboard + Node Exporter Full
  │   ├── node-exporter :9100
  │   └── MinIO         :9002
  └── K3s cluster
      ├── Traefik (ingress + TLS termination)
      ├── cert-manager (Let's Encrypt auto-renewal)
      ├── ArgoCD (GitOps auto-sync)
      ├── portfolio pod  → ai-devops.pp.ua
      └── llm-api pod   → llm.ai-devops.pp.ua
            ├── :8000 (API)
            ├── :30800 (metrics NodePort → Prometheus)
            └── → windows-host:8080 (llama-server)

Router (public IP)
  ├── :80  → ubuntu-server (ACME challenge)
  └── :443 → ubuntu-server (HTTPS)
```

## Repository Structure

```
SysOps_to_DevOps/
├── .github/workflows/
│   ├── llm-api.yml        # Build + push to GHCR
│   ├── deploy.yml         # Deploy to server
│   └── validate.yml       # Validate configs
├── ansible/               # IaC — Ansible roles
├── docker/
│   └── monitoring/
│       ├── docker-compose.yml
│       ├── prometheus.yml              # Scrape configs
│       └── grafana-llm-dashboard.json  # LLM dashboard
├── k8s/
│   ├── portfolio/         # ArgoCD app + site manifests
│   └── llm-api-app.yaml   # ArgoCD app for LLM API
├── llm-api/
│   ├── app/
│   │   ├── main.py        # FastAPI + Prometheus metrics
│   │   └── requirements.txt
│   ├── k8s/               # Deployment, Service, Ingress
│   ├── tests/
│   │   └── test_api.sh    # 6-test suite
│   └── Dockerfile
├── terraform/             # MinIO S3 backend
└── docs/
```

## Key Achievements

- **End-to-end GitOps**: git push → GitHub Actions → GHCR → ArgoCD → K3s → live in <2 min
- **Real HTTPS**: automated TLS with cert-manager + Let's Encrypt, auto-renewal
- **Self-hosted AI**: 35B parameter LLM on consumer GPU, exposed via production API
- **Full observability**: custom Prometheus metrics + Grafana dashboard with real benchmarks
- **Security**: API Key authentication, TLS 1.3
- **Verified performance**: 28–30 tok/s generation on RTX 3050 — measured, not estimated
