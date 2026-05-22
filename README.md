# SysOps to DevOps

Personal DevOps learning path built from scratch — from Windows workstation to production Kubernetes with self-hosted LLM inference.

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
  - Auto-deploy on push to `docker/**`

- [x] **Step 6: Infrastructure as Code (Ansible)**
  - Roles: docker, portainer, monitoring
  - Idempotent playbook: `ansible-playbook ansible/site.yml`
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

- [x] **Step 10: Portfolio site with HTTPS (Variant A)**
  - Static site deployed via ArgoCD from `k8s/portfolio/`
  - Traefik ingress + cert-manager + Let's Encrypt (TLS 1.3)
  - Domain: ai-devops.pp.ua
  - Full GitOps: git push → ArgoCD sync → live update

- [x] **Step 11: Self-hosted LLM API (Variant B)**
  - FastAPI proxy to local Qwen3-35B (llama.cpp, CUDA)
  - Docker image built via GitHub Actions → pushed to GHCR
  - Deployed to K3s via ArgoCD auto-sync
  - HTTPS endpoint: llm.ai-devops.pp.ua
  - Security: Traefik IP whitelist middleware (internal network only)
  - OpenAI-compatible API (`/v1/chat/completions`)

## Infrastructure Map

```
Windows (192.168.100.15)
  └── llama-server (Qwen3-35B, RTX 3050, port 8080)
  └── VS Code + Continue.dev → local LLM autocomplete

Ubuntu 22.04 (192.168.100.203)
  ├── Docker containers
  │   ├── Portainer     :9000
  │   ├── Prometheus    :9091
  │   ├── Grafana       :3000
  │   ├── node-exporter :9100
  │   └── MinIO         :9002/:9003
  └── K3s cluster
      ├── Traefik (ingress)
      ├── cert-manager (TLS)
      ├── ArgoCD (GitOps)
      ├── portfolio pod → ai-devops.pp.ua
      └── llm-api pod  → llm.ai-devops.pp.ua → 192.168.100.15:8080

Router (176.36.254.118)
  ├── :80  → 192.168.100.203 (HTTP / ACME challenge)
  └── :443 → 192.168.100.203 (HTTPS)
```

## Repository Structure

```
SysOps_to_DevOps/
├── .github/workflows/     # GitHub Actions CI/CD
├── ansible/               # IaC — Ansible roles
├── docker/                # Docker Compose configs
│   ├── monitoring/        # Prometheus + Grafana
│   └── portainer/
├── k8s/                   # Kubernetes manifests
│   ├── portfolio/         # ArgoCD app + site manifests
│   └── cert-manager/
├── llm-api/               # Self-hosted LLM API
│   ├── app/               # FastAPI application
│   ├── k8s/               # K8s deployment manifests
│   └── Dockerfile
├── terraform/             # Terraform IaC
└── docs/                  # Step-by-step documentation
```

## Key Achievements

- **End-to-end GitOps**: `git push` → GitHub Actions → GHCR → ArgoCD → K3s → live
- **Real HTTPS**: automated certificate management with cert-manager + Let's Encrypt
- **Self-hosted AI**: 35B parameter LLM running locally, exposed via production-grade API
- **Security**: Traefik middleware for IP-based access control
- **Full observability**: Prometheus metrics + Grafana dashboards for host monitoring