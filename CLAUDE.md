# CLAUDE.md

  This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

  ## Project Overview
  A personal DevOps learning path transitioning from a Windows workstation to a production-grade Kubernetes (K3s) environment. The project
  features a self-hosted LLM inference API, a full GitOps pipeline, real-time observability, and a multi-layered security stack.

  ## Architecture

  ### GitOps & CI/CD Pipeline
  The project follows a strict GitOps workflow:
  1. **Code Change**: `git push` to GitHub.
  2. **CI**: GitHub Actions builds Docker images and pushes them to GitHub Container Registry (GHCR).
  3. **CD**: ArgoCD detects changes in the `k8s/` manifests and synchronizes the state to the K3s cluster.

  ### Infrastructure & Orchestration
  - **IaC**:
    - `ansible/`: Configuration management for Ubuntu hosts (Docker, Portainer, Monitoring).
    - `terraform/`: Provisioning of infrastructure components (e.g., MinIO S3 backend).
  - **Kubernetes (K3s)**: Managed via ArgoCD. Key components include `cert-manager` for TLS and `Traefik` as the ingress controller.

  ### LLM API Service
  A FastAPI proxy (`llm-api/`) that provides an OpenAI-compatible interface. It forwards requests to a `llama-server` running on a local Windows
  host.
  - **Observability**: Integrated with Prometheus to track `llm_requests_total`, `llm_tokens_generated_total`, `llm_request_duration_seconds`, and
   `llm_tokens_per_second`.

  ### Security Stack
  A layered defense strategy:
  `Cloudflare (WAF/Edge) -> iptables (Network filtering) -> Traefik (Ingress) -> CrowdSec (Local) / Fail2ban (AWS)`
  - **Local:** CrowdSec + firewall-bouncer (780 scenarios)
  - **AWS (t3.micro):** Fail2ban SSH jail (~20MB). CrowdSec not viable on t3.micro.

  ### Monitoring Pipeline (AWS -> Local)
  - **SSH tunnel:** local server `192.168.100.203:9092` -> AWS Prometheus `10.43.1.187:9090`
  - **Federation:** local Prometheus scrapes `/federate` every 60s
  - **Grafana:** dashboard `AWS K3s - System` (uid: aws-k3s-system)
  - **Scripts:** `scripts/aws-tunnel.sh`, `scripts/mem-track.sh`

  ## Common Commands

  ### Testing & Validation
  - **Test LLM API**: `bash llm-api/tests/test_api.sh <endpoint_url>` (e.g., `https://llm.ai-devops.pp.ua`)
  - **Validate K8s manifests**: Check `k8s/` directory for changes before pushing.

  ### Infrastructure Status
  - **Check K3s Nodes/Pods**: `kubectl get nodes && kubectl get pods -A`
  - **Check ArgoCD Apps**: `kubectl get app -n argocd`
  - **Check Docker Containers**: `docker ps`
  - **Check LLM API Health**: `curl https://llm.ai-devops.pp.ua/health`

  ### Local LLM (Windows/llama-server)
  - **Check process**: `Get-Process llama-server`
  - **Test local API**: `curl http://localhost:8080/health`

  ## Directory Structure
  - `ansible/`: Configuration management roles.
  - `docker/`: Docker Compose files for local services (monitoring, portainer).
  - `k8s/`: Kubernetes manifests for ArgoCD GitOps.
  - `llm-api/`: FastAPI proxy service for LLM inference.
  - `terraform/`: Infrastructure provisioning code.
  - `docs/`: Project documentation and checklists.