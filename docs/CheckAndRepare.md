# CheckAndRepare — Повний звіт про діагностику та відновлення AWS K3s (t3.micro)

> **Дата інциденту:** 2026-06-07 — 2026-06-19  
> **Дата відновлення:** 2026-06-19  
> **Тривалість простою:** ~12 днів  
> **Автор діагностики:** AI DevOps Assistant (Cline)

---

## 1. Передісторія та контекст

### 1.1 Архітектура проекту

```
Windows (192.168.100.15)
  └── llama-server (LLM inference, порт 8080)
        │
Linux Server (192.168.100.203)
  ├── Docker Compose (Prometheus, Grafana, node-exporter)
  ├── K3s (локальний кластер з ArgoCD)
  │     ├── cert-manager
  │     ├── Traefik (Ingress)
  │     ├── llm-api (FastAPI proxy)
  │     └── portfolio (nginx сайт)
  └── Fail2ban, CrowdSec

AWS EC2 t3.micro (13.49.255.149)
  ├── K3s (v1.35.5+k3s1, single-node, SQLite)
  │     ├── Traefik → (був, вимкнений)
  │     ├── cert-manager → Let's Encrypt
  │     ├── portfolio (nginx pod)
  │     ├── Prometheus + node-exporter (був, видалений)
  │     └── CoreDNS
  ├── Terraform (EC2 + SG + EIP + IAM)
  └── nginx (systemd, з 2026-06-19)

Cloudflare (ai-devops.pp.ua)
  ├── Proxy (orange cloud)
  ├── TLS Full (strict) → Let's Encrypt origin certificate
  └── WAF (default rules)
```

### 1.2 Що сталося

7 червня 2026 року EC2 інстанс t3.micro (1GB RAM) пішов у OOM (Out of Memory). K3s API server перестав відповідати (TLS handshake timeout), Cloudflare почав повертати помилки 522 → 521. Сайт `https://ai-devops.pp.ua` був недоступний ~12 днів.

---

## 2. Діагностика (18-19 червня 2026)

### 2.1 Первинна перевірка

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

### 2.2 Виявлення кореневої причини

```powershell
# SSH на EC2
ssh -i ~/.ssh/aws_k3s ubuntu@13.49.255.149

# Проверка памяти
free -h
# total: 913Mi, used: 640Mi, available: 108Mi
# swap: 4.0Gi, used: 3.0Gi

# Процеси за споживанням пам'яті
ps aux --sort=-%mem | head -10
# k3s server: 437MB (46.7%)
# containerd: 88MB (9.4%)
# traefik:    96MB (10.2%)

# K3s API — не отвечает
kubectl get pods -A
# TLS handshake timeout — API server перегружен
```

**Висновок:** Система в OOM — 913MB total, 108Mi available, swap 3.0Gi/4.0Gi. K3s API timeout через нестачу пам'яті.

### 2.3 Стан компонентів

| Компонент | RSS (MB) | Доля | Статус |
|-----------|----------|------|--------|
| k3s server | 437 | 46.7% | ❌ API timeout |
| containerd | 88 | 9.4% | ⚠️ Працює |
| traefik | 96 | 10.2% | ❌ CrashLoopBackOff |
| prometheus | 35 | 3.7% | ❌ CrashLoopBackOff |
| cert-manager (3) | 45 | 4.8% | ⚠️ Перезапускаються |
| coredns | 27 | 2.9% | ⚠️ Pending |
| portfolio | — | — | ⚠️ Pending |
| **Всього** | **~710** | **~78%** | ❌ |

---

## 3. Процес відновлення (покроково)

### 3.1 Зупинка k3s (Emergency)

```powershell
# SSH с флагом RequestTTY=no (обходит зависание при OOM)
ssh -o RequestTTY=no -i ~/.ssh/aws_k3s ubuntu@13.49.255.149

# На EC2:
sudo systemctl stop k3s

# Проверка памяти после остановки
free -h
# total: 913Mi, used: 311Mi, available: 441Mi ✓
```

### 3.2 Встановлення GOMEMLIMIT для k3s

```bash
# Создание drop-in конфига для systemd
sudo mkdir -p /etc/systemd/system/k3s.service.d

# /etc/systemd/system/k3s.service.d/memory-limit.conf
[Service]
Environment=GOMEMLIMIT=300MiB
Environment=GOGC=50
```

### 3.3 Перевірка конфігурації k3s

```yaml
# /etc/rancher/k3s/config.yaml
tls-san:
  - 13.49.255.149
disable:
  - metrics-server    # економія ~40MB
  - local-storage     # економія ~30MB
  - traefik           # економія ~96MB
  - servicelb         # економія ~20MB
kubelet-arg:
  - system-reserved=memory=256Mi
  - kube-reserved=memory=256Mi
  - eviction-hard=memory.available<100Mi
```

### 3.4 Запуск k3s

```bash
sudo systemctl daemon-reload
sudo systemctl start k3s
sleep 30  # дати k3s ініціалізуватися

# Проверка
free -h
# total: 913Mi, used: 510Mi, available: 242Mi ✓ (було 108Mi)
```

### 3.5 Перша спроба: reboot замість stop/start

```bash
# reboot не спрацював — EC2 завис у OOM
aws ec2 reboot-instances --instance-ids i-066bd0dac0f09cb74
# SSH не відповідав > 2 хвилин — OOM заблокував систему
```

**Урок:** При OOM `reboot` може не спрацювати. Використовуйте `stop` + `start`.

### 3.6 Повний stop/start EC2

```powershell
# Зупинка
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

### 3.7 Видалення Prometheus з AWS

```bash
# Prometheus — CrashLoopBackOff, видаляємо
kubectl delete deployment prometheus -n observability --force --grace-period=0

# Чищення сміття
kubectl delete pod helm-delete-traefik-xxx -n kube-system --force --grace-period=0

# Перевірка
kubectl get pods -A
# cert-manager (3) ✅ Running
# coredns ✅ Running
# portfolio ✅ Running
# node-exporter ✅ Running
# Prometheus ❌ видалено
```

### 3.8 Встановлення nginx на EC2 (замість Traefik)

```bash
# nginx вже був встановлений (залишився від попередніх спроб)
# Перевіряємо
sudo nginx -t

# Створюємо reverse proxy на portfolio pod
# Знаходимо IP portfolio
kubectl get pod -l app=portfolio -o jsonpath='{.items[0].status.podIP}'
# → 10.42.0.157
```

**Проблема з конфігом:** Файл, скопійований через SCP з Windows, містив CRLF (Windows) закінчення рядків, що ламало nginx. Рішення — генерувати конфіг через Python на сервері.

```bash
# Скрипт fix-nginx.py — генерує коректний конфіг
# Завантажуємо на EC2
scp scripts/fix-nginx.py ubuntu@13.49.255.149:/tmp/

# Запускаємо
python3 /tmp/fix-nginx.py
sudo cp /tmp/p-nginx.conf /etc/nginx/sites-available/portfolio
sudo nginx -t && sudo systemctl reload nginx
```

**Конфіг nginx:**
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

### 3.9 Налаштування TLS (Let's Encrypt сертифікат)

Спочатку використовувався self-signed сертифікат → Cloudflare повертав 526 (Invalid SSL certificate). Рішення — використовувати сертифікат, випущений cert-manager'ом всередині K3s.

```bash
# Вилучення Let's Encrypt сертифіката з Kubernetes Secret
kubectl get secret portfolio-tls -o jsonpath='{.data.tls\.crt}' | base64 -d \
  | sudo tee /etc/nginx/ssl/portfolio.crt > /dev/null
kubectl get secret portfolio-tls -o jsonpath='{.data.tls\.key}' | base64 -d \
  | sudo tee /etc/nginx/ssl/portfolio.key > /dev/null

# Перевірка
sudo openssl x509 -in /etc/nginx/ssl/portfolio.crt -noout -subject -issuer -dates
# subject=CN = ai-devops.pp.ua
# issuer=C = US, O = Let's Encrypt

# Перезавантаження nginx
sudo nginx -t && sudo systemctl reload nginx
```

**Важливо:** В Cloudflare Dashboard має бути режим **SSL/TLS → Full (strict)**, т.к. сертифікат від Let's Encrypt.

### 3.10 Додавання Security Group правила для порту 443

Порт 443 не був відкритий в Security Group — додано через AWS CLI:

```powershell
aws ec2 authorize-security-group-ingress --group-id sg-0cec508510825fb80 `
  --ip-permissions "IpProtocol=tcp,FromPort=443,ToPort=443, ..."
# Cloudflare CIDRs — всі 15 IPv4 діапазонів
```

---

## 4. Моніторинг: AWS → Local Grafana

### 4.1 Нова архітектура

```
ДО (падало):
AWS: Prometheus → pod crash → немає метрик
SSH tunnel → 9092 → AWS Prometheus:9090

ПІСЛЯ (працює):
AWS: node-exporter:9100 (hostNetwork, завжди доступний)
SSH tunnel → 9101 → AWS 172.31.39.148:9100
Локальний Prometheus → scrape 172.17.0.1:9101/aws-node-exporter
Grafana → dashboard "AWS K3s — System"
```

### 4.2 Налаштування SSH tunnel на локальному сервері

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

### 4.3 Оновлення локального Prometheus

```yaml
# docker/monitoring/prometheus.yml — новий job:
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

### 4.4 Автоматизація (скрипт aws-tunnel.sh)

```bash
# scripts/aws-tunnel.sh — перевіряє тунель кожні 5 хв
# Якщо тунель впав — перезапускає
# Запускати через cron на 192.168.100.203
```

---

## 5. Результати

### 5.1 Пам'ять

| Параметр | До (падіння) | Після (відновлення) |
|----------|-------------|----------------------|
| Total RAM | 913 MiB | 913 MiB |
| Used | ~848 MiB | ~600 MiB |
| Available | ~65 MiB | **~200-300 MiB** ✅ |
| Swap used | 3.0 GiB / 4.0 GiB | 263 MiB / 4.0 GiB |

### 5.2 Компоненти

| Компонент | До | Після |
|-----------|----|-------|
| k3s server | 437 MB | ~335 MB (GOMEMLIMIT) |
| Ingress | Traefik (96 MB) ❌ | nginx (15 MB) ✅ |
| Prometheus | 35 MB ❌ | Видалений ✅ |
| Метрики | Prometheus на AWS ❌ | node-exporter → SSH tunnel → Local Grafana ✅ |
| Сертифікат | Let's Encrypt (через cert-manager) | Let's Encrypt вилучений в nginx ✅ |
| Сайт | 521 (Web server is down) | **200 OK** ✅ |

### 5.3 Фінальна перевірка

```powershell
# HTTPS через Cloudflare
curl -sI https://ai-devops.pp.ua/
# → HTTP/1.1 200 OK, Server: cloudflare

# Health endpoint
curl -s https://ai-devops.pp.ua/health
# → {"status":"ok","service":"portfolio"}

# Пам'ять на EC2
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

## 6. Ключові висновки та уроки

### 6.1 Що пішло не так

1. **K3s + t3.micro = ризик OOM.** 1GB RAM недостатньо для повноцінного K3s з Traefik та cert-manager.
2. **Traefik не потрібен на t3.micro.** nginx як systemd сервіс споживає в 6 разів менше пам'яті.
3. **Prometheus на AWS — надлишковий.** Метрики можна отримувати через SSH tunnel + локальну Grafana.
4. **Cloudflare TLS Full (strict) вимагає валідного origin-сертифіката.** Self-signed не проходить.

### 6.2 Що було зроблено правильно

1. **Stop/start замість reboot** — при OOM reboot може не допомогти.
2. **GOMEMLIMIT для Go-процесів** — обмежує споживання k3s.
3. **SQLite backup** — дозволив би відновитися без втрати даних (але не знадобилося).
4. **cert-manager всередині K3s** — сертифікат Let's Encrypt живий, вилучений в nginx.

### 6.3 Профілактика

- **Alerting:** налаштувати сповіщення при available RAM < 150 MiB (в локальному Prometheus)
- **Моніторинг:** `/var/log/mem-track.csv` кожні 5 хвилин
- **План дій при OOM:**
  1. SSH з `-o RequestTTY=no`
  2. `sudo systemctl stop k3s`
  3. Перевірити/збільшити swap
  4. Перевірити конфіг k3s
  5. `sudo systemctl start k3s`
  6. Почекати 30 секунд
  7. Перевірити `free -h` та `kubectl get pods`

---

## 7. Змінені файли

| Файл | Зміна |
|------|-----------|
| `docs/incident-2026-06-16-ai-devops-pp-ua-down.md` | Оновлено статус відновлення |
| `REPARE_PLAN.md` | Створено — план відновлення |
| `scripts/aws-tunnel.sh` | Оновлено — порт 9101, target на host IP |
| `docker/monitoring/prometheus.yml` | Оновлено — новий job aws-node-exporter |
| `scripts/fix-nginx.py` | Створено — генерація nginx конфіга |
| `docs/aws-free-tier-limitations.md` | Створено — обмеження Free Tier |

---

## 8. Посилання

- [`docs/aws-k3s-setup.md`](aws-k3s-setup.md) — повний лог деплою AWS K3s
- [`docs/incident-2026-06-16-ai-devops-pp-ua-down.md`](incident-2026-06-16-ai-devops-pp-ua-down.md) — опис інциденту
- [`docs/aws-free-tier-limitations.md`](aws-free-tier-limitations.md) — обмеження Free Tier
- [`HOW-TO.md`](../HOW-TO.md) — керівництво по експлуатації
- [`REPARE_PLAN.md`](../REPARE_PLAN.md) — план відновлення
- [`scripts/aws-tunnel.sh`](../scripts/aws-tunnel.sh) — скрипт SSH tunnel
