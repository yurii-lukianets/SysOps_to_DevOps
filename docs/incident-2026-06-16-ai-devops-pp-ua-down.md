# Інцидент: ai-devops.pp.ua недоступний (Error 522)

**Дата:** 2026-06-16  
**Час діагностики:** 06:37 — 11:37 (Europe/Kiev)  
**Тривалість простою:** ~12 днів (з 7 червня 2026 по 19 червня 2026)  
**Дата відновлення:** 2026-06-19 07:53 (Europe/Kiev)  
**Статус:** ✅ Повністю відновлено (200 OK)  
**Рішення:** nginx (systemd) на EC2 замість Traefik + моніторинг через SSH tunnel на локальний сервер

---

## Симптоми

- Сайт `https://ai-devops.pp.ua/` не відповідає
- Cloudflare показує помилку **522 — Connection timed out**
- Пізніше змінилася на **521 — Web server is down**

---

## Діагностика (виконані дії)

### 1. DNS резолвінг
```bash
nslookup ai-devops.pp.ua 1.1.1.1
```
**Результат:** DNS резолвить у IP Cloudflare (104.21.17.56, 172.67.222.86) — OK

### 2. HTTP доступність
```bash
curl -vI https://ai-devops.pp.ua --connect-timeout 10
```
**Результат:** Cloudflare підключається до origin, але не отримує відповідь — тайм-аут

### 3. AWS CLI перевірка
```bash
aws sts get-caller-identity
```
**Результат:** Акаунт `056885487909`, користувач `devops-admin`

### 4. EC2 інстанс
```bash
aws ec2 describe-instances --query "Reservations[*].Instances[*].[InstanceId,State.Name,PublicIpAddress,PrivateIpAddress,InstanceType,Tags[?Key=='Name'].Value|[0]]" --output table
```
**Результат:**
- InstanceId: `i-066bd0dac0f09cb74`
- State: `running`
- Public IP: `13.49.255.149`
- Private IP: `172.31.39.148`
- Type: `t3.micro`
- Name: `k3s-node`

### 5. Security Groups
```bash
aws ec2 describe-security-groups --group-ids sg-0cec508510825fb80 --query "SecurityGroups[0].IpPermissions[?IpProtocol=='tcp']" --output json
```
**Результат:** Порти 80/443 відкриті для Cloudflare CIDRs, SSH (22) тільки з IP `176.36.254.118/32`

### 6. Load Balancer
```bash
aws elbv2 describe-load-balancers --query "LoadBalancers[*].[LoadBalancerName,DNSName,State.Code,Scheme]" --output table
```
**Результат:** Load Balancer не використовується

### 7. Elastic IP
```bash
aws ec2 describe-addresses --query "Addresses[*].[PublicIp,AllocationId,InstanceId]" --output table
```
**Результат:** EIP `13.49.255.149` прив'язаний до інстансу

### 8. Пряме підключення до інстансу
```bash
curl -vI http://13.49.255.149 --connect-timeout 5
curl -v telnet://13.49.255.149:22 --connect-timeout 5
```
**Результат:** Порти 80 та 22 не відповідають — тайм-аут

### 9. SSM Session Manager
```bash
aws ssm describe-instance-information --query "InstanceInformationList[*].[InstanceId,ComputerName,PingStatus,LastPingDateTime,AgentVersion]" --output table
```
**Результат:**
- PingStatus: **ConnectionLost**
- LastPingDateTime: **2026-06-07T08:27:58** (~9 днів тому)
- AgentVersion: 3.3.4121.0

### 10. CloudWatch метрики
```bash
aws cloudwatch get-metric-statistics --namespace AWS/EC2 --metric-name CPUUtilization --dimensions Name=InstanceId,Value=i-066bd0dac0f09cb74 --start-time 2026-06-15T00:00:00Z --end-time 2026-06-16T00:00:00Z --period 3600 --statistics Average --output table
```
**Результат:** CPU ~7% — інстанс виконує роботу, але мережа не проходить

### 11. Консольний вивід
```bash
aws ec2 get-console-output --instance-id i-066bd0dac0f09cb74 --output text
```
**Результат:** Ядро Linux 6.8.0-1057-aws, Ubuntu 22.04

### 12. SSH підключення
```bash
ssh -o StrictHostKeyChecking=no -i C:\Users\LUKAS\.ssh\aws_k3s ubuntu@13.49.255.149
```
**Результат:** SSH працює з ключем `aws_k3s`

### 13. Стан k3s
```bash
sudo systemctl status k3s --no-pager
sudo kubectl get pods -A --no-headers
sudo kubectl get svc -A --no-headers
free -h
ps aux --sort=-%mem | head -10
```
**Результат:**
- k3s: active (running) але API server не відповідає (TLS handshake timeout)
- Memory: 913Mi total, ~600Mi used, ~300Mi free
- k3s server process: **437MB RSS (46.7%)**
- containerd: 88MB (9.4%)
- traefik: 96MB (10.2%)
- prometheus: 35MB (3.7%)
- cert-manager: 27MB (2.8%)
- coredns: 27MB (2.9%)

### 14. Відновлення (первинне)
```bash
# Перезагрузка EC2
aws ec2 reboot-instances --instance-ids i-066bd0dac0f09cb74

# Остановка k3s и очистка
sudo systemctl stop k3s
sudo pkill -9 -f containerd
sudo rm -rf /var/lib/rancher/k3s

# Обновление конфига k3s (отключение traefik, servicelb)
# /etc/rancher/k3s/config.yaml:
# disable:
#   - metrics-server
#   - local-storage
#   - traefik
#   - servicelb

# Установка ограничений памяти
# /etc/systemd/system/k3s.service.d/memory-limit.conf:
# [Service]
# Environment=GOMEMLIMIT=300MiB
# Environment=GOGC=50
```

---

## Аналіз

| Проверка | Статус | Комментарий |
|----------|--------|-------------|
| DNS | ✅ OK | Резолвить у Cloudflare |
| Cloudflare → Origin | ❌ 522→521 | Мережа працює, але немає web server |
| EC2 State | ✅ running | Інстанс у стані running |
| CPU | ✅ ~7% | Інстанс живий |
| SSM Agent | ❌ ConnectionLost | З 7 червня 2026 |
| HTTP/HTTPS (пряме) | ❌→✅ 521 | Мережу відновлено після reboot |
| SSH | ✅ OK | Працює з ключем aws_k3s |
| Security Group | ✅ OK | Порти відкриті для Cloudflare |
| Load Balancer | — | Не використовується |
| k3s API | ❌ | TLS handshake timeout |
| RAM | ❌ | k3s = 437MB на 913MB total |

---

## Коренева причина

**k3s занадто важкий для t3.micro (1GB RAM)**

- Процес k3s server: **437MB RSS (46.7%)**
- containerd: **88MB (9.4%)**
- Інші pod'и (traefik, cert-manager, prometheus, coredns): **~185MB**
- Разом: **~710MB** на машині з **913MB RAM**
- Результат: системний swap, TLS handshake timeout, API server не відповідає

Навіть після:
- Відключення traefik та servicelb
- Встановлення GOMEMLIMIT=300MiB
- Повного перевстановлення k3s

**k3s server process = 437MB** — це мінімальний розмір Go процесу k3s, його не можна зменшити.

---

## Відновлено (фінальне)

1. ✅ EC2 інстанс перезавантажено (stop/start, не reboot)
2. ✅ Мережа працює (Cloudflare → EC2: port 80/443 open)
3. ✅ SSH доступний з ключем `C:\Users\LUKAS\.ssh\aws_k3s`
4. ✅ SSM Agent підключився
5. ✅ k3s запущено стабільно
6. ✅ Ingress: nginx (systemd) — замінив Traefik
7. ✅ HTTPS: 200 OK через Cloudflare
8. ✅ TLS: Let's Encrypt сертифікат (вилучено з cert-manager K8s Secret)
9. ✅ Prometheus видалено з AWS (економія ~35MB)
10. ✅ Моніторинг: node-exporter → SSH tunnel → локальний Prometheus (192.168.100.203)
11. ✅ Memory: ~200-300Mi available (було ~65Mi)

---

## Використані інструменти

| Інструмент | Призначення |
|------------|------------|
| `nslookup` | Перевірка DNS резолвінгу |
| `curl` | Перевірка HTTP доступності |
| `aws sts get-caller-identity` | Перевірка AWS CLI |
| `aws ec2 describe-instances` | Перевірка EC2 |
| `aws ec2 describe-security-groups` | Перевірка Security Groups |
| `aws elbv2 describe-load-balancers` | Перевірка Load Balancer |
| `aws ec2 describe-addresses` | Перевірка Elastic IP |
| `aws ssm describe-instance-information` | Перевірка SSM Agent |
| `aws cloudwatch get-metric-statistics` | Перевірка CPU метрик |
| `aws ec2 get-console-output` | Консольний вивід |
| `aws ec2 stop-instances / start-instances` | Stop/Start EC2 |
| `aws ec2 authorize-security-group-ingress` | Додавання правила 443 |
| `ssh` | Підключення до інстансу |
| `scp` | Копіювання файлів |
| `kubectl` | Управління k3s кластером |
| `systemctl` | Управління k3s сервісом |
| `free -h` | Перевірка пам'яті |
| `ps aux` | Перевірка процесів |
| `nginx` | Reverse proxy для portfolio |
| `openssl` | Генерація/перевірка сертифікатів |
| `python3` | Генерація конфігів (уникаючи CRLF проблем) |

---

## Рекомендації (виконано)

| Рекомендація | Статус |
|--------------|--------|
| Встановити nginx на EC2 замість Traefik | ✅ Виконано |
| Налаштувати reverse proxy на portfolio pod | ✅ Виконано |
| Видалити Prometheus з AWS | ✅ Виконано |
| Налаштувати моніторинг через SSH tunnel + локальний Prometheus | ✅ Виконано |
| Оновити Security Group (порт 443) | ✅ Виконано |
| Встановити GOMEMLIMIT=300MiB для k3s | ✅ Виконано |
| Використовувати Let's Encrypt сертифікат (з cert-manager) | ✅ Виконано |

---

## Поточний стан (фінальний, 19 червня 2026 07:53)

| Компонент | Статус |
|-----------|--------|
| EC2 | ✅ running |
| Мережа | ✅ Cloudflare → EC2 працює |
| SSH | ✅ Доступний |
| k3s | ✅ Запущено, API відповідає |
| Ingress | ✅ nginx (systemd) — працює |
| TLS | ✅ Let's Encrypt (cert-manager → nginx) |
| Сайт | ✅ 200 OK |
| Prometheus на AWS | ❌ Видалено |
| Моніторинг | ✅ node-exporter → SSH tunnel → локальний Prometheus/Grafana |

### Деталі відновлення (детальний лог)

Повний покроковий звіт про процес відновлення див. у:
- [`docs/CheckAndRepare.md`](CheckAndRepare.md) — повний лог діагностики та відновлення
- [`docs/aws-free-tier-limitations.md`](aws-free-tier-limitations.md) — обмеження Free Tier
