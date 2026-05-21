# SysOps to DevOps

Personal DevOps learning path built from scratch.

## Stack
- Local LLM: Qwen3 via llama-server (RTX 3050, 8GB VRAM)
- Containerization: Docker on Ubuntu 22.04
- CI/CD: GitHub Actions
- IaC: Ansible
- Cloud: AWS Free Tier
- AI-assisted development: local LLM + Claude Code CLI

## Progress
- [x] Step 1: Windows workstation setup
- [x] Step 2: GitHub repository
- [x] Step 3: Docker infrastructure on Ubuntu 22.04
  - Portainer CE (container management)
  - Server: Intel Core2 Quad 2.4GHz, 4GB RAM, 98GB disk

## Infrastructure
| Service        | Host            | Port | Notes                    |
|----------------|-----------------|------|--------------------------|
| Portainer      | 192.168.100.203 | 9000 | Docker management UI     |
| Prometheus     | 192.168.100.203 | 9091 | Metrics collection       |
| Grafana        | 192.168.100.203 | 3000 | Dashboards (ID 1860)     |
| Node Exporter  | 192.168.100.203 | 9100 | Host metrics             |
- [x] Step 5: CI/CD pipeline
  - GitHub Actions: validate.yml + deploy.yml
  - Self-hosted runner on Ubuntu server (devops-lab)
  - Auto-deploy on push to docker/**
- [x] Step 6: Infrastructure as Code (Ansible)
  - Roles: docker, portainer, monitoring
  - Idempotent playbook: ansible-playbook ansible/site.yml
  - Local connection (ansible_connection=local)
