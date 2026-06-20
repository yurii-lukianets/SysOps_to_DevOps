# AWS Free Tier Limitations — Практичний досвід

> **Дата:** 2026-06-19
> **Регіон:** eu-north-1 (Stockholm)
> **Проєкт:** K3s single-node cluster + portfolio website

---

## 1. EC2 — t3.micro (1 vCPU, 1 GiB RAM)

### Ліміти Free Tier

| Параметр | Значення | Коментар |
|----------|----------|-------------|
| Тип інстанса | t3.micro (1 vCPU, 1 GiB) | Тільки цей тип безкоштовний в eu-north-1 |
| Ліміт годин | 750 годин/місяць | ~31 день безперервної роботи |
| Період | 12 місяців | З моменту створення акаунта |
| EBS (диск) | 30 GB gp2/gp3 безкоштовно | Наш інстанс: 20 GB gp2 |
| EIP (Elastic IP) | Безкоштовно тільки прив'язаний до running instance | Відв'язка → ~$3.6/місяць |

### Реальна доступна пам'ять

```
t3.micro spec:     1 GiB (1024 MiB)
EC2 overhead:      ~111 MiB (гіпервізор, xen)
Фактично:        913 MiB total
```

### Провал: OOM на t3.micro з K3s

**Хронологія:**
1. 2026-06-02 — K3s встановлено, все працює (~200Mi available)
2. 2026-06-03 — Деплой cert-manager + portfolio. Пам'ять: ~100Mi available
3. 2026-06-03 — OOM fix: відключено metrics-server, local-storage, 4GB swap
4. 2026-06-07 — Система впала (OOM). k3s API не відповідає (TLS handshake timeout)
5. 2026-06-07 → 2026-06-16 — Простій ~9 днів
6. 2026-06-16 — Діагностика: k3s server 437MB (46.7%), traefik 96MB (10.2%)
7. 2026-06-19 — Повне відновлення: nginx замість traefik, Prometheus видалено

**Причина падіння:**
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

**Висновок:** K3s + traefik + prometheus + cert-manager **не вміщуються** в 1GB RAM.

---

## 2. Рішення для Free Tier

### ✅ Працююче рішення (поточне)

| Компонент | Заміна | Економія RAM |
|-----------|--------|-------------|
| Traefik (96 MB) | nginx systemd (15 MB) | ~80 MB |
| Prometheus (35 MB) | Видалено. Метрики через node-exporter → SSH tunnel → локальна Grafana | ~35 MB |
| metrics-server | Відключено | ~40 MB |
| local-storage | Відключено | ~30 MB |

**Підсумок:** ~200-300 MB available. Стабільно.

### ❌ Що НЕ працює на t3.micro

| Сервіс | Причина |
|--------|---------|
| CrowdSec | Вимагає ~120-200 MB RAM |
| Grafana (на тому ж інстансі) | Вимагає ~150-250 MB RAM |
| Більше 1-2 додаткових pod'ів | Кожен pod ~20-50 MB |
| metrics-server | ~40 MB overhead |
| ArgoCD | Не сумісний з t3.micro |

---

## 3. EBS (Диски)

| Параметр | Значення |
|----------|----------|
| Тип | gp2 |
| Розмір | 20 GB |
| Free Tier | 30 GB (використано 20 з 30) |
| Використано | ~5.6 GB (Ubuntu + K3s + логи) |
| iops | 100 (базовий для gp2) |

**Важливо:** При stop/start інстанса EBS не втрачається, але втрачається публічний IP (якщо не використовувати EIP).

---

## 4. Elastic IP (EIP)

| Стан | Вартість |
|-----------|-----------|
| Прив'язаний до running instance | Безкоштовно |
| Прив'язаний до stopped instance | Безкоштовно |
| Відв'язаний (не прив'язаний ні до чого) | ~$0.005/год (~$3.6/міс) |

**Правило:** Ніколи не відв'язувати EIP, якщо інстанс не буде permanently terminated.

---

## 5. Data Transfer

| Напрямок | Free Tier | Наше використання |
|-------------|-----------|-------------------|
| З інтернету в EC2 | 100 GB/міс | << 1 GB/міс (тільки Cloudflare + SSH) |
| З EC2 в інтернет | 100 GB/міс | Мінімально |
| Між EC2 та S3 (той же регіон) | Безкоштовно | Тільки Terraform state |
| Cloudflare → EC2 | Безкоштовно (через Cloudflare) | Все зовнішнє навантаження |

---

## 6. S3

| Параметр | Значення |
|----------|----------|
| Bucket | `sysops-devops-tfstate-056885487909` |
| Розмір | < 1 GB |
| Free Tier | 5 GB |
| API запити | PAY_PER_REQUEST, копійки |
| Versioning | Увімкнено (історія Terraform state) |

---

## 7. DynamoDB

| Параметр | Значення |
|----------|----------|
| Таблиця | `terraform-locks` |
| Billing mode | PAY_PER_REQUEST |
| Free Tier | 25 GB |
| Використано | < 1 MB |

---

## 8. CloudWatch

| Метрика | Період | Free Tier |
|---------|--------|-----------|
| CPUUtilization | 5 хвилин | Безкоштовно (до 10 метрик) |
| StatusCheckFailed | 1 хвилина | Безкоштовно |
| Custom metrics | — | Не використовуються (дорого) |

**Важливо:** CloudWatch Logs не використовуються (пишемо логи локально на EC2 через fail2ban, journalctl).

---

## 9. Security Group Rules

**Поточні правила (обов'язкові для роботи):**

| Порт | Призначення | CIDR |
|------|-----------|------|
| 22 | SSH (адмін) | `176.36.254.118/32` |
| 80 | HTTP → nginx → portfolio | Cloudflare CIDRs |
| 443 | HTTPS (Let's Encrypt + Cloudflare) | Cloudflare CIDRs |
| 6443 | K8s API (якщо потрібен kubectl) | `176.36.254.118/32` |

**Порти НЕ повинні бути відкриті:**
- `30000-32767` (NodePort) — не потрібен, traefik відключено
- `9100` (node-exporter) — тільки через SSH tunnel
- `9090` (Prometheus) — видалено з AWS

---

## 10. Рекомендації для Free Tier

### DO
- Використовувати t3.micro **тільки** для легких навантажень
- Замінити Traefik на nginx (економія ~80 MB)
- Винести моніторинг на окремий сервер (локальний)
- Відключити все зайве: metrics-server, local-storage, servicelb
- Встановити GOMEMLIMIT=300MiB для k3s
- Використовувати swap 4GB (на 1GB RAM)
- Налаштувати eviction-hard=memory.available<100Mi

### DON'T
- Не запускати Grafana на тому ж інстансі
- Не запускати CrowdSec
- Не запускати більше 1-2 додаткових сервісів в K3s
- Не використовувати ArgoCD
- Не зберігати великі об'єми даних на EBS
- Не видаляти EIP без необхідності

### Monitor
- `free -h` — щоденно перевіряти available RAM
- `/var/log/mem-track.csv` — кожні 5 хвилин логується
- CloudWatch — CPU + StatusCheck (безкоштовно)
- Якщо available RAM < 100 MiB — негайно зупинити зайві pod'и

---

## 11. Посилання

- [AWS Free Tier](https://aws.amazon.com/free/)
- [EC2 Pricing](https://aws.amazon.com/ec2/pricing/)
- [t3.micro specs](https://aws.amazon.com/ec2/instance-types/t3/)
