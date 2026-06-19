# AWS Free Tier Limitations — Практический опыт

> **Дата:** 2026-06-19
> **Регион:** eu-north-1 (Stockholm)
> **Проект:** K3s single-node cluster + portfolio website

---

## 1. EC2 — t3.micro (1 vCPU, 1 GiB RAM)

### Лимиты Free Tier

| Параметр | Значение | Комментарий |
|----------|----------|-------------|
| Тип инстанса | t3.micro (1 vCPU, 1 GiB) | Только этот тип бесплатен в eu-north-1 |
| Лимит часов | 750 часов/месяц | ~31 день непрерывной работы |
| Период | 12 месяцев | С момента создания аккаунта |
| EBS (диск) | 30 GB gp2/gp3 бесплатно | Наш инстанс: 20 GB gp2 |
| EIP (Elastic IP) | Бесплатно только привязанный к running instance | Отвязка → ~$3.6/месяц |

### Реальная доступная память

```
t3.micro spec:     1 GiB (1024 MiB)
EC2 overhead:      ~111 MiB (гипервизор, xen)
Фактически:        913 MiB total
```

### Провал: OOM на t3.micro с K3s

**Хронология:**
1. 2026-06-02 — K3s установлен, всё работает (~200Mi available)
2. 2026-06-03 — Деплой cert-manager + portfolio. Память: ~100Mi available
3. 2026-06-03 — OOM fix: отключены metrics-server, local-storage, 4GB swap
4. 2026-06-07 — Система упала (OOM). k3s API не отвечает (TLS handshake timeout)
5. 2026-06-07 → 2026-06-16 — Простой ~9 дней
6. 2026-06-16 — Диагностика: k3s server 437MB (46.7%), traefik 96MB (10.2%)
7. 2026-06-19 — Полное восстановление: nginx вместо traefik, Prometheus удалён

**Причина падения:**
```
K3s Server:         437 MB  (46.7%)
containerd:          88 MB  (9.4%)
Traefik:             96 MB  (10.2%)
Cert-manager (3):    45 MB  (4.8%)
Prometheus:          35 MB  (3.7%)
CoreDNS:             27 MB  (2.9%)
OS + fail2ban:      120 MB  (12.8%)
─────────────────────────────────
Total:              ~848 MB  (92.9% of 913 MiB)
Available:           ~65 MB  (7.1%)
```

**Вывод:** K3s + traefik + prometheus + cert-manager **не помещаются** в 1GB RAM.

---

## 2. Решения для Free Tier

### ✅ Работающее решение (текущее)

| Компонент | Замена | Экономия RAM |
|-----------|--------|-------------|
| Traefik (96 MB) | nginx systemd (15 MB) | ~80 MB |
| Prometheus (35 MB) | Удалён. Метрики через node-exporter → SSH tunnel → локальная Grafana | ~35 MB |
| metrics-server | Отключён | ~40 MB |
| local-storage | Отключён | ~30 MB |

**Итог:** ~200-300 MB available. Стабильно.

### ❌ Что НЕ работает на t3.micro

| Сервис | Причина |
|--------|---------|
| CrowdSec | Требует ~120-200 MB RAM |
| Grafana (на том же инстансе) | Требует ~150-250 MB RAM |
| Больше 1-2 дополнительных pod'ов | Каждый pod ~20-50 MB |
| metrics-server | ~40 MB overhead |
| ArgoCD | Не совместим с t3.micro |

---

## 3. EBS (Диски)

| Параметр | Значение |
|----------|----------|
| Тип | gp2 |
| Размер | 20 GB |
| Free Tier | 30 GB (использовано 20 из 30) |
| Использовано | ~5.6 GB (Ubuntu + K3s + логи) |
| iops | 100 (базовый для gp2) |

**Важно:** При stop/start инстанса EBS не теряется, но теряется публичный IP (если не использовать EIP).

---

## 4. Elastic IP (EIP)

| Состояние | Стоимость |
|-----------|-----------|
| Привязан к running instance | Бесплатно |
| Привязан к stopped instance | Бесплатно |
| Отвязан (не привязан ни к чему) | ~$0.005/час (~$3.6/мес) |

**Правило:** Никогда не отвязывать EIP, если инстанс не будет permanently terminated.

---

## 5. Data Transfer

| Направление | Free Tier | Наше использование |
|-------------|-----------|-------------------|
| Из интернета в EC2 | 100 GB/мес | << 1 GB/мес (только Cloudflare + SSH) |
| Из EC2 в интернет | 100 GB/мес | Минимально |
| Между EC2 и S3 (тот же регион) | Бесплатно | Только Terraform state |
| Cloudflare → EC2 | Бесплатно (через Cloudflare) | Вся внешняя нагрузка |

---

## 6. S3

| Параметр | Значение |
|----------|----------|
| Bucket | `sysops-devops-tfstate-056885487909` |
| Размер | < 1 GB |
| Free Tier | 5 GB |
| API запросы | PAY_PER_REQUEST, копейки |
| Versioning | Включено (история Terraform state) |

---

## 7. DynamoDB

| Параметр | Значение |
|----------|----------|
| Таблица | `terraform-locks` |
| Billing mode | PAY_PER_REQUEST |
| Free Tier | 25 GB |
| Использовано | < 1 MB |

---

## 8. CloudWatch

| Метрика | Период | Free Tier |
|---------|--------|-----------|
| CPUUtilization | 5 минут | Бесплатно (до 10 метрик) |
| StatusCheckFailed | 1 минута | Бесплатно |
| Сustom metrics | — | Не используются (дорого) |

**Важно:** CloudWatch Logs не используются (пишем логи локально на EC2 через fail2ban, journalctl).

---

## 9. Security Group Rules

**Текущие правила (обязательны для работы):**

| Порт | Назначение | CIDR |
|------|-----------|------|
| 22 | SSH (админ) | `176.36.254.118/32` |
| 80 | HTTP → nginx → portfolio | Cloudflare CIDRs |
| 443 | HTTPS (Let's Encrypt + Cloudflare) | Cloudflare CIDRs |
| 6443 | K8s API (если нужно kubectl) | `176.36.254.118/32` |

**Порты НЕ должны быть открыты:**
- `30000-32767` (NodePort) — не нужен, traefik отключён
- `9100` (node-exporter) — только через SSH tunnel
- `9090` (Prometheus) — удалён с AWS

---

## 10. Рекомендации для Free Tier

### DO
- Использовать t3.micro **только** для лёгких нагрузок
- Заменить Traefik на nginx (экономия ~80 MB)
- Вынести мониторинг на отдельный сервер (локальный)
- Отключить всё лишнее: metrics-server, local-storage, servicelb
- Установить GOMEMLIMIT=300MiB для k3s
- Использовать swap 4GB (на 1GB RAM)
- Настроить eviction-hard=memory.available<100Mi

### DON'T
- Не запускать Grafana на том же инстансе
- Не запускать CrowdSec
- Не запускать более 1-2 дополнительных сервисов в K3s
- Не использовать ArgoCD
- Не хранить большие объёмы данных на EBS
- Не удалять EIP без необходимости

### Monitor
- `free -h` — ежедневно проверять available RAM
- `/var/log/mem-track.csv` — каждые 5 минут логируется
- CloudWatch — CPU + StatusCheck (бесплатно)
- Если available RAM < 100 MiB — немедленно остановить лишние pod'ы

---

## 11. Ссылки

- [AWS Free Tier](https://aws.amazon.com/free/)
- [EC2 Pricing](https://aws.amazon.com/ec2/pricing/)
- [t3.micro specs](https://aws.amazon.com/ec2/instance-types/t3/)