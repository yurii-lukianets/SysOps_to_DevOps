# CheckAndRepare — Полный отчёт о диагностике и восстановлении AWS K3s (t3.micro)

> **Дата инцидента:** 2026-06-07 — 2026-06-19  
> **Дата восстановления:** 2026-06-19  
> **Продолжительность простоя:** ~12 дней  
> **Автор диагностики:** AI DevOps Assistant (Cline)

---

## 1. Предыстория и контекст

### 1.1 Архитектура проекта

```
Windows (192.168.100.15)
  └── llama-server (LLM inference, порт 8080)
        │
Linux Server (192.168.100.203)
  ├── Docker Compose (Prometheus, Grafana, node-exporter)
  ├── K3s (локальный кластер с ArgoCD)
  │     ├── cert-manager
  │     ├── Traefik (Ingress)
  │     ├── llm-api (FastAPI proxy)
  │     └── portfolio (nginx сайт)
  └── Fail2ban, CrowdSec

AWS EC2 t3.micro (13.49.255.149)
  ├── K3s (v1.35.5+k3s1, single-node, SQLite)
  │     ├── Traefik → (был, отключён)
  │     ├── cert-manager → Let's Encrypt
  │     ├── portfolio (nginx pod)
  │     ├── Prometheus + node-exporter (был, удалён)
  │     └── CoreDNS
  ├── Terraform (EC2 + SG + EIP + IAM)
  └── nginx (systemd, с 2026-06-19)

Cloudflare (ai-devops.pp.ua)
  ├── Proxy (orange cloud)
  ├── TLS Full (strict) → Let's Encrypt origin certificate
  └── WAF (default rules)
```

### 1.2 Что произошло

7 июня 2026 года EC2 инстанс t3.micro (1GB RAM) ушёл в OOM (Out of Memory). K3s API server перестал отвечать (TLS handshake timeout), Cloudflare начал возвращать ошибки 522 → 521. Сайт `https://ai-devops.pp.ua` был недоступен ~12 дней.

---

## 2. Диагностика (18-19 июня 2026)

### 2.1 Первичная проверка

```powershell
# Windows — проверка DNS
nslookup ai-devops.pp.ua 1.1.1.1
# → Cloudflare IPs (104.21.17.56, 172.67.222.86) — DNS OK

# Проверка HTTP через Cloudflare
curl -vI https://ai-devops.pp.ua --connect-timeout 10
# → 521 — Web server is down

# AWS CLI — проверка аккаунта
aws sts get-caller-identity
# → arn:aws:iam::056885487909:user/devops-admin — OK

# EC2 статус
aws ec2 describe-instances --instance-ids i-066bd0dac0f09cb74 --region eu-north-1
# → State: running
```

### 2.2 Выявление корневой причины

```powershell
# SSH на EC2
ssh -i ~/.ssh/aws_k3s ubuntu@13.49.255.149

# Проверка памяти
free -h
# total: 913Mi, used: 640Mi, available: 108Mi
# swap: 4.0Gi, used: 3.0Gi

# Процессы по потреблению памяти
ps aux --sort=-%mem | head -10
# k3s server: 437MB (46.7%)
# containerd: 88MB (9.4%)
# traefik:    96MB (10.2%)

# K3s API — не отвечает
kubectl get pods -A
# TLS handshake timeout — API server перегружен
```

**Вывод:** Система в OOM — 913MB total, 108Mi available, swap 3.0Gi/4.0Gi. K3s API timeout из-за нехватки памяти.

### 2.3 Состояние компонентов

| Компонент | RSS (MB) | Доля | Статус |
|-----------|----------|------|--------|
| k3s server | 437 | 46.7% | ❌ API timeout |
| containerd | 88 | 9.4% | ⚠️ Работает |
| traefik | 96 | 10.2% | ❌ CrashLoopBackOff |
| prometheus | 35 | 3.7% | ❌ CrashLoopBackOff |
| cert-manager (3) | 45 | 4.8% | ⚠️ Перезапускаются |
| coredns | 27 | 2.9% | ⚠️ Pending |
| portfolio | — | — | ⚠️ Pending |
| **Всего** | **~710** | **~78%** | ❌ |

---

## 3. Процесс восстановления (пошагово)

### 3.1 Остановка k3s (Emergency)

```powershell
# SSH с флагом RequestTTY=no (обходит зависание при OOM)
ssh -o RequestTTY=no -i ~/.ssh/aws_k3s ubuntu@13.49.255.149

# На EC2:
sudo systemctl stop k3s

# Проверка памяти после остановки
free -h
# total: 913Mi, used: 311Mi, available: 441Mi ✓
```

### 3.2 Установка GOMEMLIMIT для k3s

```bash
# Создание drop-in конфига для systemd
sudo mkdir -p /etc/systemd/system/k3s.service.d

# /etc/systemd/system/k3s.service.d/memory-limit.conf
[Service]
Environment=GOMEMLIMIT=300MiB
Environment=GOGC=50
```

### 3.3 Проверка конфигурации k3s

```yaml
# /etc/rancher/k3s/config.yaml
tls-san:
  - 13.49.255.149
disable:
  - metrics-server    # экономия ~40MB
  - local-storage     # экономия ~30MB
  - traefik           # экономия ~96MB
  - servicelb         # экономия ~20MB
kubelet-arg:
  - system-reserved=memory=256Mi
  - kube-reserved=memory=256Mi
  - eviction-hard=memory.available<100Mi
```

### 3.4 Запуск k3s

```bash
sudo systemctl daemon-reload
sudo systemctl start k3s
sleep 30  # дать k3s инициализироваться

# Проверка
free -h
# total: 913Mi, used: 510Mi, available: 242Mi ✓ (было 108Mi)
```

### 3.5 Первая попытка: reboot вместо stop/start

```bash
# reboot не сработал — EC2 завис в OOM
aws ec2 reboot-instances --instance-ids i-066bd0dac0f09cb74
# SSH не отвечал > 2 минут — OOM заблокировал систему
```

**Урок:** При OOM `reboot` может не сработать. Используйте `stop` + `start`.

### 3.6 Полный stop/start EC2

```powershell
# Остановка
aws ec2 stop-instances --instance-ids i-066bd0dac0f09cb74 --region eu-north-1
# Wait → "stopped"

# Запуск
aws ec2 start-instances --instance-ids i-066bd0dac0f09cb74 --region eu-north-1
# Wait ~60s → "running"

# SSH
ssh -i ~/.ssh/aws_k3s ubuntu@13.49.255.149
free -h
# total: 913Mi, used: 523Mi, available: 232Mi ✓
```

### 3.7 Удаление Prometheus из AWS

```bash
# Prometheus — CrashLoopBackOff, удаляем
kubectl delete deployment prometheus -n observability --force --grace-period=0

# Чистка мусора
kubectl delete pod helm-delete-traefik-xxx -n kube-system --force --grace-period=0

# Проверка
kubectl get pods -A
# cert-manager (3) ✅ Running
# coredns ✅ Running
# portfolio ✅ Running
# node-exporter ✅ Running
# Prometheus ❌ удалён
```

### 3.8 Установка nginx на EC2 (вместо Traefik)

```bash
# nginx уже был установлен (остался от предыдущих попыток)
# Проверяем
sudo nginx -t

# Создаём reverse proxy на portfolio pod
# Находим IP portfolio
kubectl get pod -l app=portfolio -o jsonpath='{.items[0].status.podIP}'
# → 10.42.0.157
```

**Проблема с конфигом:** Файл, скопированный через SCP с Windows, содержал CRLF (Windows) окончания строк, что ломало nginx. Решение — генерировать конфиг через Python на сервере.

```bash
# Скрипт fix-nginx.py — генерирует корректный конфиг
# Загружаем на EC2
scp scripts/fix-nginx.py ubuntu@13.49.255.149:/tmp/

# Запускаем
python3 /tmp/fix-nginx.py
sudo cp /tmp/p-nginx.conf /etc/nginx/sites-available/portfolio
sudo nginx -t && sudo systemctl reload nginx
```

**Конфиг nginx:**
```nginx
server {
    listen 80;
    server_name ai-devops.pp.ua;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ai-devops.pp.ua;

    ssl_certificate /etc/nginx/ssl/portfolio.crt;
    ssl_certificate_key /etc/nginx/ssl/portfolio.key;

    location / {
        proxy_pass http://10.42.0.157:80;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }

    location /health {
        proxy_pass http://10.42.0.157:80;
        proxy_set_header Host $host;
    }
}
```

### 3.9 Настройка TLS (Let's Encrypt сертификат)

Изначально использовался self-signed сертификат → Cloudflare возвращал 526 (Invalid SSL certificate). Решение — использовать сертификат, выпущенный cert-manager'ом внутри K3s.

```bash
# Извлечение Let's Encrypt сертификата из Kubernetes Secret
kubectl get secret portfolio-tls -o jsonpath='{.data.tls\.crt}' | base64 -d \
  | sudo tee /etc/nginx/ssl/portfolio.crt > /dev/null
kubectl get secret portfolio-tls -o jsonpath='{.data.tls\.key}' | base64 -d \
  | sudo tee /etc/nginx/ssl/portfolio.key > /dev/null

# Проверка
sudo openssl x509 -in /etc/nginx/ssl/portfolio.crt -noout -subject -issuer -dates
# subject=CN = ai-devops.pp.ua
# issuer=C = US, O = Let's Encrypt

# Перезагрузка nginx
sudo nginx -t && sudo systemctl reload nginx
```

**Важно:** В Cloudflare Dashboard должен быть режим **SSL/TLS → Full (strict)**, т.к. сертификат от Let's Encrypt.

### 3.10 Добавление Security Group правила для порта 443

Порт 443 не был открыт в Security Group — добавлено через AWS CLI:

```powershell
aws ec2 authorize-security-group-ingress --group-id sg-0cec508510825fb80 `
  --ip-permissions "IpProtocol=tcp,FromPort=443,ToPort=443, ..."
# Cloudflare CIDRs — все 15 IPv4 диапазонов
```

---

## 4. Мониторинг: AWS → Local Grafana

### 4.1 Новая архитектура

```
ДО (падало):
AWS: Prometheus → pod crash → нет метрик
SSH tunnel → 9092 → AWS Prometheus:9090

ПОСЛЕ (работает):
AWS: node-exporter:9100 (hostNetwork, всегда доступен)
SSH tunnel → 9101 → AWS 172.31.39.148:9100
Локальный Prometheus → scrape 172.17.0.1:9101/aws-node-exporter
Grafana → dashboard "AWS K3s — System"
```

### 4.2 Настройка SSH tunnel на локальном сервере

```bash
# На 192.168.100.203:
ssh -i ~/.ssh/aws_k3s \
    -o StrictHostKeyChecking=no \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3 \
    -f -L 0.0.0.0:9101:172.31.39.148:9100 \
    -N ubuntu@13.49.255.149

# Проверка
curl http://localhost:9101/metrics | head -3
# → go_gc_duration_seconds... — метрики node-exporter
```

### 4.3 Обновление локального Prometheus

```yaml
# docker/monitoring/prometheus.yml — новый job:
  - job_name: aws-node-exporter
    scrape_interval: 60s
    scrape_timeout: 10s
    static_configs:
      - targets: ['172.17.0.1:9101']
    metrics_path: /metrics
```

```bash
# На 192.168.100.203:
docker compose restart prometheus
```

### 4.4 Автоматизация (скрипт aws-tunnel.sh)

```bash
# scripts/aws-tunnel.sh — проверяет туннель каждые 5 мин
# Если туннель упал — перезапускает
# Запускать через cron на 192.168.100.203
```

---

## 5. Результаты

### 5.1 Память

| Параметр | До (падение) | После (восстановление) |
|----------|-------------|----------------------|
| Total RAM | 913 MiB | 913 MiB |
| Used | ~848 MiB | ~600 MiB |
| Available | ~65 MiB | **~200-300 MiB** ✅ |
| Swap used | 3.0 GiB / 4.0 GiB | 263 MiB / 4.0 GiB |

### 5.2 Компоненты

| Компонент | До | После |
|-----------|----|-------|
| k3s server | 437 MB | ~335 MB (GOMEMLIMIT) |
| Ingress | Traefik (96 MB) ❌ | nginx (15 MB) ✅ |
| Prometheus | 35 MB ❌ | Удалён ✅ |
| Метрики | Prometheus на AWS ❌ | node-exporter → SSH tunnel → Local Grafana ✅ |
| Сертификат | Let's Encrypt (через cert-manager) | Let's Encrypt извлечён в nginx ✅ |
| Сайт | 521 (Web server is down) | **200 OK** ✅ |

### 5.3 Финальная проверка

```powershell
# HTTPS через Cloudflare
curl -sI https://ai-devops.pp.ua/
# → HTTP/1.1 200 OK, Server: cloudflare

# Health endpoint
curl -s https://ai-devops.pp.ua/health
# → {"status":"ok","service":"portfolio"}

# Память на EC2
ssh ubuntu@13.49.255.149 "free -h"
# → total: 913Mi, available: 308Mi

# k3s pods
kubectl get pods -A | grep -v Completed
# → cert-manager (3) ✅ Running
# → coredns ✅ Running
# → portfolio ✅ Running
# → node-exporter ✅ Running
```

---

## 6. Ключевые выводы и уроки

### 6.1 Что пошло не так

1. **K3s + t3.micro = риск OOM.** 1GB RAM недостаточно для полноценного K3s с Traefik и cert-manager.
2. **Traefik не нужен на t3.micro.** nginx как systemd сервис потребляет в 6 раз меньше памяти.
3. **Prometheus на AWS — избыточен.** Метрики можно получать через SSH tunnel + локальную Grafana.
4. **Cloudflare TLS Full (strict) требует валидного origin-сертификата.** Self-signed не проходит.

### 6.2 Что было сделано правильно

1. **Stop/start вместо reboot** — при OOM reboot может не помочь.
2. **GOMEMLIMIT для Go-процессов** — ограничивает потребление k3s.
3. **SQLite backup** — позволил бы восстановиться без потери данных (но не понадобилось).
4. **cert-manager внутри K3s** — сертификат Let's Encrypt жив, извлечён в nginx.

### 6.3 Профилактика

- **Alerting:** настроить оповещение при available RAM < 150 MiB (в локальном Prometheus)
- **Мониторинг:** `/var/log/mem-track.csv` каждые 5 минут
- **План действий при OOM:**
  1. SSH с `-o RequestTTY=no`
  2. `sudo systemctl stop k3s`
  3. Проверить/увеличить swap
  4. Проверить конфиг k3s
  5. `sudo systemctl start k3s`
  6. Подождать 30 секунд
  7. Проверить `free -h` и `kubectl get pods`

---

## 7. Изменённые файлы

| Файл | Изменение |
|------|-----------|
| `docs/incident-2026-06-16-ai-devops-pp-ua-down.md` | Обновлён статус восстановления |
| `REPARE_PLAN.md` | Создан — план восстановления |
| `scripts/aws-tunnel.sh` | Обновлён — порт 9101, target на host IP |
| `docker/monitoring/prometheus.yml` | Обновлён — новый job aws-node-exporter |
| `scripts/fix-nginx.py` | Создан — генерация nginx конфига |
| `docs/aws-free-tier-limitations.md` | Создан — ограничения Free Tier |

---

## 8. Ссылки

- [`docs/aws-k3s-setup.md`](aws-k3s-setup.md) — полный лог деплоя AWS K3s
- [`docs/incident-2026-06-16-ai-devops-pp-ua-down.md`](incident-2026-06-16-ai-devops-pp-ua-down.md) — описание инцидента
- [`docs/aws-free-tier-limitations.md`](aws-free-tier-limitations.md) — ограничения Free Tier
- [`HOW-TO.md`](../HOW-TO.md) — руководство по эксплуатации
- [`REPARE_PLAN.md`](../REPARE_PLAN.md) — план восстановления
- [`scripts/aws-tunnel.sh`](../scripts/aws-tunnel.sh) — скрипт SSH tunnel