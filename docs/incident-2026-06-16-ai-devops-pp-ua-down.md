# Инцидент: ai-devops.pp.ua недоступен (Error 522)

**Дата:** 2026-06-16  
**Время диагностики:** 06:37 — 11:37 (Europe/Kiev)  
**Продолжительность простоя:** ~9 дней (с 7 июня 2026)  
**Статус:** Частично восстановлен (сеть работает, нужен ingress controller)

---

## Симптомы

- Сайт `https://ai-devops.pp.ua/` не отвечает
- Cloudflare показывает ошибку **522 — Connection timed out**
- Позже сменилась на **521 — Web server is down**

---

## Диагностика (выполненные действия)

### 1. DNS резолвинг
```bash
nslookup ai-devops.pp.ua 1.1.1.1
```
**Результат:** DNS резолвит в IP Cloudflare (104.21.17.56, 172.67.222.86) — OK

### 2. HTTP доступность
```bash
curl -vI https://ai-devops.pp.ua --connect-timeout 10
```
**Результат:** Cloudflare подключается к origin, но не получает ответ — таймаут

### 3. AWS CLI проверка
```bash
aws sts get-caller-identity
```
**Результат:** Аккаунт `056885487909`, пользователь `devops-admin`

### 4. EC2 инстанс
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
**Результат:** Порты 80/443 открыты для Cloudflare CIDRs, SSH (22) только с IP `176.36.254.118/32`

### 6. Load Balancer
```bash
aws elbv2 describe-load-balancers --query "LoadBalancers[*].[LoadBalancerName,DNSName,State.Code,Scheme]" --output table
```
**Результат:** Load Balancer не используется

### 7. Elastic IP
```bash
aws ec2 describe-addresses --query "Addresses[*].[PublicIp,AllocationId,InstanceId]" --output table
```
**Результат:** EIP `13.49.255.149` привязан к инстансу

### 8. Прямое подключение к инстансу
```bash
curl -vI http://13.49.255.149 --connect-timeout 5
curl -v telnet://13.49.255.149:22 --connect-timeout 5
```
**Результат:** Порты 80 и 22 не отвечают — таймаут

### 9. SSM Session Manager
```bash
aws ssm describe-instance-information --query "InstanceInformationList[*].[InstanceId,ComputerName,PingStatus,LastPingDateTime,AgentVersion]" --output table
```
**Результат:**
- PingStatus: **ConnectionLost**
- LastPingDateTime: **2026-06-07T08:27:58** (~9 дней назад)
- AgentVersion: 3.3.4121.0

### 10. CloudWatch метрики
```bash
aws cloudwatch get-metric-statistics --namespace AWS/EC2 --metric-name CPUUtilization --dimensions Name=InstanceId,Value=i-066bd0dac0f09cb74 --start-time 2026-06-15T00:00:00Z --end-time 2026-06-16T00:00:00Z --period 3600 --statistics Average --output table
```
**Результат:** CPU ~7% — инстанс выполняет работу, но сеть не проходит

### 11. Консольный вывод
```bash
aws ec2 get-console-output --instance-id i-066bd0dac0f09cb74 --output text
```
**Результат:** Ядро Linux 6.8.0-1057-aws, Ubuntu 22.04

### 12. SSH подключение
```bash
ssh -o StrictHostKeyChecking=no -i C:\Users\LUKAS\.ssh\aws_k3s ubuntu@13.49.255.149
```
**Результат:** SSH работает с ключом `aws_k3s`

### 13. Состояние k3s
```bash
sudo systemctl status k3s --no-pager
sudo kubectl get pods -A --no-headers
sudo kubectl get svc -A --no-headers
free -h
ps aux --sort=-%mem | head -10
```
**Результат:**
- k3s: active (running) но API server не отвечает (TLS handshake timeout)
- Memory: 913Mi total, ~600Mi used, ~300Mi free
- k3s server process: **437MB RSS (46.7%)**
- containerd: 88MB (9.4%)
- traefik: 96MB (10.2%)
- prometheus: 35MB (3.7%)
- cert-manager: 27MB (2.8%)
- coredns: 27MB (2.9%)

### 14. Восстановление
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

## Анализ

| Проверка | Статус | Комментарий |
|----------|--------|-------------|
| DNS | ✅ OK | Резолвит в Cloudflare |
| Cloudflare → Origin | ❌ 522→521 | Сеть работает, но нет web server |
| EC2 State | ✅ running | Инстанс в состоянии running |
| CPU | ✅ ~7% | Инстанс活着 |
| SSM Agent | ❌ ConnectionLost | С 7 июня 2026 |
| HTTP/HTTPS (прямое) | ❌→✅ 521 | Сеть восстановлена после reboot |
| SSH | ✅ OK | Работает с ключом aws_k3s |
| Security Group | ✅ OK | Порты открыты для Cloudflare |
| Load Balancer | — | Не используется |
| k3s API | ❌ | TLS handshake timeout |
| RAM | ❌ | k3s = 437MB на 913MB total |

---

## Корневая причина

**k3s слишком тяжёлый для t3.micro (1GB RAM)**

- Процесс k3s server: **437MB RSS (46.7%)**
- containerd: **88MB (9.4%)**
- Остальные pod'ы (traefik, cert-manager, prometheus, coredns): **~185MB**
- Итого: **~710MB** на машине с **913MB RAM**
- Результат: системный swap, TLS handshake timeout, API server не отвечает

Даже после:
- Отключения traefik и servicelb
- Установки GOMEMLIMIT=300MiB
- Полной переустановки k3s

**k3s server process = 437MB** — это минимальный размер Go процесса k3s, его нельзя уменьшить.

---

## Восстановлено

1. ✅ EC2 инстанс перезагружен
2. ✅ Сеть работает (Cloudflare → EC2: port 80/443 open)
3. ✅ SSH доступен с ключом `C:\Users\LUKAS\.ssh\aws_k3s`
4. ✅ SSM Agent подключился
5. ✅ k3s запущен (но API server медленный)
6. ❌ Нет ingress controller (traefik отключен)
7. ❌ k3s API server перегружен (не отвечает на kubectl)

---

## Использованные инструменты

| Инструмент | Назначение |
|------------|------------|
| `nslookup` | Проверка DNS резолвинга |
| `curl` | Проверка HTTP доступности |
| `aws sts get-caller-identity` | Проверка AWS CLI |
| `aws ec2 describe-instances` | Проверка EC2 |
| `aws ec2 describe-security-groups` | Проверка Security Groups |
| `aws elbv2 describe-load-balancers` | Проверка Load Balancer |
| `aws ec2 describe-addresses` | Проверка Elastic IP |
| `aws ssm describe-instance-information` | Проверка SSM Agent |
| `aws cloudwatch get-metric-statistics` | Проверка CPU метрик |
| `aws ec2 get-console-output` | Консольный вывод |
| `aws ec2 reboot-instances` | Перезагрузка EC2 |
| `ssh` | Подключение к инстансу |
| `kubectl` | Управление k3s кластером |
| `systemctl` | Управление k3s сервисом |
| `free -h` | Проверка памяти |
| `ps aux` | Проверка процессов |

---

## Рекомендации

### Проблема: k3s слишком тяжёлый для t3.micro

**Вариант 1: Замена k3s на nginx (рекомендуется)**
```bash
# Установка nginx на EC2
sudo apt update && sudo apt install -y nginx
sudo systemctl enable nginx

# Настройка reverse proxy для сайта
# /etc/nginx/sites-available/ai-devops.pp.ua:
server {
    listen 80;
    server_name ai-devops.pp.ua;
    location / {
        proxy_pass http://localhost:3000;  # или другой порт приложения
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```
**Потребление памяти:** ~10-20MB (вместо ~700MB)

**Вариант 2: Docker Compose вместо k3s**
```bash
# Установка Docker
curl -fsSL https://get.docker.com | sh
# Запуск приложения через docker-compose
docker compose up -d
```
**Потребление памяти:** ~50-100MB

**Вариант 3: Оставить k3s, но с minimal конфигурацией**
- Отключить ВСЕ компоненты кроме API server
- Deploy только ingress controller + приложение
- **Риск:** нестабильность из-за нехватки RAM

**Вариант 4: Upgrade до t3.small (2GB RAM)**
- **Нет** — не входит в бесплатный план AWS

---

## Текущее состояние (по состоянию на 11:37)

| Компонент | Статус |
|-----------|--------|
| EC2 | ✅ running |
| Сеть | ✅ Cloudflare → EC2 работает |
| SSH | ✅ Доступен |
| k3s | ⚠️ Запущен, но API перегружен |
| Ingress | ❌ traefik отключен, nginx не установлен |
| Сайт | ❌ 521 (Web server is down) |

### Для восстановления сайта необходимо:
1. Установить nginx на EC2 (или docker)
2. Настроить reverse proxy на приложение
3. Убедиться, что приложение (portfolio) запущено