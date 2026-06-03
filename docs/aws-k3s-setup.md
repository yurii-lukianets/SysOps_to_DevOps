# AWS K3s Setup — Step-by-Step Log

**Дата:** 2026-06-02
**Region:** eu-north-1 (Stockholm)
**Free Tier only:** t3.micro (2 vCPU, 1GB RAM)

---

## Підсумок

| Компонент | Значення |
|-----------|----------|
| EC2 Instance | `i-066bd0dac0f09cb74` (t3.micro) |
| Public IP | `13.49.255.149` |
| Private IP | `172.31.39.148` |
| AMI | `ami-095e44eb80ff16c3f` (Ubuntu 22.04.5 LTS) |
| Security Group | `sg-0cec508510825fb80` |
| Key Pair | `k3s-key` (~/.ssh/aws_k3s) |
| K3s version | v1.35.5+k3s1 |
| kubectl з Windows | `~/.kube/config-aws` |

---

## 1. Підготовка Windows

### 1.1 Встановлення AWS CLI v2

```powershell
winget install --id Amazon.AWSCLI -e --accept-source-agreements --accept-package-agreements
# aws-cli/2.34.57 Python/3.14.5 Windows/11 exe/AMD64
```

### 1.2 Налаштування credentials

Скопійовано з Ubuntu (`~/.aws/credentials`) через `aws configure set`:

```powershell
aws configure set region eu-north-1
aws configure set output json
aws configure set aws_access_key_id AKIAQ2PVDVES25IGSER4
aws configure set aws_secret_access_key <SECRET>
aws sts get-caller-identity
# arn:aws:iam::056885487909:user/devops-admin ✅
```

**⚠️ AWS CLI v2 на Windows не приймає файли конфігурації, записані через `Out-File`!**
Тільки `aws configure set` або ручне редагування.

### 1.3 Створення окремого SSH ключа для AWS

```powershell
ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\aws_k3s -N '""' -C "aws-k3s-terraform"
```

Існуючий `~/.ssh/id_ed25519` зашифрований passphrase — незручно для Terraform.

---

## 2. Terraform — створення EC2

### 2.1 Структура

```
J:\SysOps_to_DevOps\terraform\aws\
├── main.tf
├── id_ed25519.pub  ← публічний ключ для aws_key_pair
└── .terraform/     ← state, providers
```

### 2.2 main.tf

```hcl
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" { region = "eu-north-1" }

data "aws_ami" "ubuntu_2204" {
  most_recent = true
  owners      = ["099720109477"]  # Canonical
  filter { name = "name", values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"] }
}

resource "aws_key_pair" "k3s" {
  key_name   = "k3s-key"
  public_key = file("${path.module}/id_ed25519.pub")
}

resource "aws_security_group" "k3s" {
  name = "k3s-sg"

  ingress {
    from_port = 22; to_port = 22; protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 80; to_port = 80; protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 443; to_port = 443; protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Kubernetes API"
    from_port = 6443; to_port = 6443; protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "K3s NodePort range"
    from_port = 30000; to_port = 32767; protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress { from_port = 0; to_port = 0; protocol = "-1"; cidr_blocks = ["0.0.0.0/0"] }
}

resource "aws_instance" "k3s" {
  ami                    = data.aws_ami.ubuntu_2204.id
  instance_type          = "t3.micro"   # Free Tier у eu-north-1
  vpc_security_group_ids = [aws_security_group.k3s.id]
  key_name               = aws_key_pair.k3s.key_name

  root_block_device { volume_size = 20; volume_type = "gp2" }
}

resource "aws_eip" "k3s" {
  instance = aws_instance.k3s.id
  domain   = "vpc"
}

output "public_ip"   { value = aws_eip.k3s.public_ip }
output "instance_id" { value = aws_instance.k3s.id }
```

### 2.3 Запуск

```bash
cd J:\SysOps_to_DevOps\terraform\aws
terraform init
terraform plan
terraform apply -auto-approve
```

**Результат:**
```
Apply complete! Resources: 2 added, 0 changed, 0 destroyed.
public_ip   = "13.49.255.149"
instance_id = "i-066bd0dac0f09cb74"
```

### 2.4 Помилки та виправлення

| Помилка | Причина | Рішення |
|---------|---------|---------|
| `t2.micro is not eligible for Free Tier` | AWS прибрав t2.micro з Free Tier у 2024+ | `instance_type = "t3.micro"` |
| `Permission denied (publickey)` | id_ed25519 зашифрований, ssh-agent не має passphrase | Створив окремий `aws_k3s` без passphrase |
| `host key changed` після перестворення | Новий інстанс = новий host key | `ssh-keygen -R 13.49.255.149` |
| `tls: failed to verify certificate` | K3s cert не включає публічний IP | Додав `tls-san: 13.49.255.149` в k3s config |

---

## 3. EC2 — підготовка

### 3.1 SSH

```powershell
ssh -i $env:USERPROFILE\.ssh\aws_k3s ubuntu@13.49.255.149
```

### 3.2 Swap 2GB (для K3s на 1GB RAM)

```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
free -h
# Swap: 2.0Gi ✅
```

---

## 4. K3s — встановлення

### 4.1 Інсталяція

```bash
curl -sfL https://get.k3s.io | sh -s - \
  --disable servicelb \
  --disable local-storage \
  --write-kubeconfig-mode 644
```

**Версія:** v1.35.5+k3s1

### 4.2 tls-san для публічного IP

```bash
echo 'tls-san:' | sudo tee -a /etc/rancher/k3s/config.yaml
echo '  - 13.49.255.149' | sudo tee -a /etc/rancher/k3s/config.yaml
sudo systemctl restart k3s
```

### 4.3 Перевірка

```bash
sudo kubectl get nodes -o wide
# ip-172-31-39-148 Ready control-plane 4m47s v1.35.5+k3s1

sudo kubectl get pods -A
# coredns, traefik, metrics-server — всі Running
```

---

## 5. kubectl з Windows

### 5.1 Копіювання kubeconfig

```powershell
ssh -i $env:USERPROFILE\.ssh\aws_k3s ubuntu@13.49.255.149 "sudo cat /etc/rancher/k3s/k3s.yaml" `
  | % { $_ -replace "127.0.0.1:6443", "13.49.255.149:6443" } `
  | Out-File $env:USERPROFILE\.kube\config-aws
```

### 5.2 Використання

```powershell
$env:KUBECONFIG = "$env:USERPROFILE\.kube\config-aws"
kubectl get nodes
kubectl get pods -A
```

### 5.3 Альтернатива: SSH tunnel

```powershell
ssh -i $env:USERPROFILE\.ssh\aws_k3s -L 6443:127.0.0.1:6443 -N ubuntu@13.49.255.149
# В іншому терміналі:
$env:KUBECONFIG = "$env:USERPROFILE\.kube\config"  # з 127.0.0.1
kubectl get nodes
```

---

## 6. Тестовий деплой

```powershell
$env:KUBECONFIG = "$env:USERPROFILE\.kube\config-aws"

kubectl create deployment nginx-test --image=nginx:alpine
kubectl expose deployment nginx-test --port=80 --type=NodePort
kubectl get svc nginx-test
# NodePort 80:30266/TCP
```

**Тест з Windows:**
```powershell
(Invoke-WebRequest http://13.49.255.149:30266/).StatusCode
# 200 ✅
```

**Cleanup:**
```powershell
kubectl delete svc,deployment nginx-test
```

---

## 7. Використання ресурсів

```
Mem:    913Mi total, ~580Mi used (K3s + traefik + coredns + metrics)
Swap:  2.0Gi total, ~260Mi used
Disk:  ~3GB used (Ubuntu + K3s)
```

**Free Tier budget:**
- t3.micro: 750 год/міс безкоштовно (12 міс)
- EBS gp2 20GB: 30GB безкоштовно
- EIP: безкоштовно поки прив'язаний до running instance
- Data transfer: 100GB/міс безкоштовно

**Прогнозована вартість:** $0.00/міс (Free Tier) + $0.01 alert

---

## 8. Деплой portfolio + cert-manager на AWS K3s

### 8.1 Структура маніфестів (перевикористано з локального кластеру)

```
k8s/portfolio/
├── configmap.yml      # HTML portfolio
├── deployment.yml     # nginx pod + Service + Ingress
└── argocd-app.yml     # НЕ застосовано на AWS (ArgoCD лише локально)
```

```powershell
$env:KUBECONFIG = "$env:USERPROFILE\.kube\config-aws"
kubectl apply -f k8s/cert-manager/cluster-issuer.yml
kubectl apply -f k8s/portfolio/configmap.yml
kubectl apply -f k8s/portfolio/deployment.yml
```

### 8.2 Зміна DNS у Cloudflare

Усі записи для `ai-devops.pp.ua` (root, www, llm, mail, ftp) → `13.49.255.149` Proxied.

### 8.3 Resource state після деплою

```
ingress: portfolio (ai-devops.pp.ua → service/portfolio:80)
ingress: cm-acme-http-solver-tg889 (challenge path → solver:8089)
pod:     portfolio-86574cc599-zhlsb  (10.42.0.11, Running)
pod:     cm-acme-http-solver-6k897  (10.42.0.12, Running)
svc:     traefik (LoadBalancer 172.31.39.148, NodePort 30599/32012)
```

---

## 9. Найскладніший баг: "Connection refused" на EIP:80

### 9.1 Хронологія спроб

| # | Що зроблено | Результат |
|---|-------------|-----------|
| 1 | K3s з `--disable servicelb` | ClusterIP Traefik, нема LB IP, EIP:80 → RST |
| 2 | Re-enable servicelb (klipper-lb) | svclb-traefik DaemonSet Running, але EIP:80 досі RST |
| 3 | `iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-ports 30599` | EIP:80 → 200 (бо Traefik слухає 30599), але cert-manager self-check з Cloudflare = 521 |
| 4 | `kubectl patch svc traefik -p '{"spec":{"loadBalancerIP":"13.49.255.149"}}'` | kube-proxy **проігнорував**, EXTERNAL-IP залишився `172.31.39.148` |
| 5 | **Видалив ручні REDIRECT правила** | EIP:80 → 200, cert-manager self-check = 200, **cert issued** ✅ |

### 9.2 Корінь проблеми: чому K3s klipler-lb не працював "з коробки"

**K3s `klipper-lb` працює виключно через iptables у просторі імен klipper-pod:**

```
svclb-traefik-<hash> (hostPort: 80/443, hostNetwork: false)
  ├── container lb-tcp-80
  │     └── iptables -t nat -I PREROUTING --dport 80 \
  │                       -j DNAT --to 10.43.110.255:80   ← Traefik ClusterIP
  └── container lb-tcp-443 (те саме для 443)
```

**Ключове**: iptables правила додаються в **мережевому просторі klipper-pod**, а не на хості. Щоб трафік від зовнішнього клієнта дійшов до цих правил, kubelet мусить зробити DNAT з host:80 → klipper-pod:80 (через механізм `hostPort`). Це і є ланка, яка ламається на AWS.

### 9.3 Те, що "мало б" працювати, але не працює

K3s Traefik Service має type `LoadBalancer` з `EXTERNAL-IP: 172.31.39.148` (приватний IP EC2). kube-proxy автоматично додає правило:

```
-A KUBE-SERVICES -d 172.31.39.148/32 -p tcp --dport 80 \
   -j KUBE-EXT-UQMCRMJZLI3FTLDP
-A KUBE-EXT-UQMCRMJZLI3FTLDP -d 0.0.0.0/0 -j KUBE-MARK-MASQ
-A KUBE-EXT-UQMCRMJZLI3FTLDP -j DNAT --to 10.42.0.6:8000  ← Traefik pod
```

Це правило **має б працювати** для зовнішнього трафіку на EIP, бо:
1. Пакет з EIP 13.49.255.149:80 приходить на eth0
2. AWS/Azure EIP виконує hairpin NAT dst→172.31.39.148 **до** netfilter
3. iptables PREROUTING бачить dst=172.31.39.148:80
4. KUBE-SERVICES спрацьовує, DNAT → Traefik pod
5. Відповідь через conntrack повертається назад

**Чому це не працювало спочатку** (до додавання REDIRECT):
- Причина досі не 100% з'ясована, але скоріш за все kube-proxy **тільки-но стартував** і KUBE-EXT правила ще не були повністю синхронізовані, або ж `ADDRTYPE match dst-type LOCAL` для EIP-прив'язки не спрацьовувало через особливості AWS hairpin NAT.

**Workaround (правильний)**: перезапуск klipper-lb pod форсує kube-proxy повністю оновити правила. Або просто почекати ~30 секунд після старту K3s.

### 9.4 Чому `loadBalancerIP: 13.49.255.149` НЕ працює

Спроба змінити Traefik Service:

```bash
kubectl patch svc traefik -n kube-system -p '{"spec":{"loadBalancerIP":"13.49.255.149"}}'
# service/traefik patched  ← Service прийняв значення
# але EXTERNAL-IP у get svc все ще 172.31.39.148
# kube-proxy НЕ оновив KUBE-EXT правила
```

**Чому**: K3s валідує `loadBalancerIP` — він мусить бути **в межах subnet'и VPC EC2** (`172.31.0.0/16`). EIP `13.49.255.149` — це **public IP ззовні VPC**, тож kube-proxy/klipper-lb мовчки відкидає це значення. У старих версіях K3s навіть повертав помилку, в нових — просто ігнорує.

**Висновок**: klipper-lb розрахований на хмарні провайдери типу AWS NLB/GCP LB, де LoadBalancer IP = приватний IP з CIDR VPC. Для AWS з EIP + Cloudflare **не змінюйте** `loadBalancerIP` — залиште `172.31.39.148`, бо це саме те, що AWS EIP hairpin NAT'ить на вході.

### 9.5 Чому ручні REDIRECT правила — це **ПОГАНО**

```bash
# Що я зробив як hack:
iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-ports 30599
iptables -t nat -A PREROUTING -p tcp --dport 443 -j REDIRECT --to-ports 32012
```

**Наче працює**, але:
- ❌ Зламана логіка kube-proxy (він вже має правильні правила для `172.31.39.148:80`, але REDIRECT їх перехоплює)
- ❌ Не переживає `systemctl restart k3s` (правила в `/etc/rancher/k3s/config.yaml`, але iptables flush при перезапуску)
- ❌ Hairpin з localhost на EIP не працює (EIP 13.49.255.149 не прив'язаний до localhost)
- ❌ cert-manager self-check повертав 521 від Cloudflare, бо REDIRECT ламав маршрут

**Правильне рішення**: **видалити REDIRECT правила**, дочекатися ~30 секунд після старту K3s, kube-proxy сам створить правильні правила для `172.31.39.148`.

```bash
sudo iptables -t nat -D PREROUTING -p tcp --dport 80 -j REDIRECT --to-ports 30599
sudo iptables -t nat -D PREROUTING -p tcp --dport 443 -j REDIRECT --to-ports 32012
```

### 9.6 Як правильно дебажити "Connection refused" на EIP

```bash
# 1. Чи слухає хост порт 80/443?
ssh ubuntu@13.49.255.149 "sudo ss -tlnp | grep -E ':80|:443'"
# Якщо нічого — klipper-lb не встановив правила

# 2. Чи є правила kube-proxy для LoadBalancer IP?
sudo iptables -t nat -L KUBE-SERVICES | grep 172.31.39.148
# Має бути: -d 172.31.39.148 --dport 80 -j KUBE-EXT-...

# 3. Чи є EXTERNAL-IP у Traefik Service?
kubectl get svc traefik -n kube-system
# EXTERNAL-IP має = приватний IP EC2

# 4. Тест з самого EC2 (hairpin):
curl -H "Host: ai-devops.pp.ua" http://172.31.39.148/  # має 502/404, не connection refused

# 5. Тест challenge endpoint:
curl http://172.31.39.148/.well-known/acme-challenge/<token>
# Має повернути key authorization, НЕ 404

# 6. Якщо 1-5 ОК, але зовнішній curl = RST:
#    → перезапустити svclb-traefik pod
kubectl delete pod -n kube-system -l app=svclb-traefik
```

### 9.7 Фінальна перевірка

```powershell
curl.exe -I https://ai-devops.pp.ua/
# HTTP/1.1 200 OK ✅
# Server: cloudflare ✅
# cert-manager: portfolio-tls Ready=True ✅
```

---

## 10. Помилки GitHub push protection

Детальніше у `docs/security/secrets-rotation.md`. Коротко:
- Перший push з AWS credentials у `.sonet_free.md` заблоковано
- Виправлено: redact + `git filter-branch` + force-push вручну
- AWS ключі ротовано

---

## 11. Наступні кроки

- [x] Деплой portfolio + cert-manager ✅
- [x] TLS cert issued ✅
- [x] HTTPS через Cloudflare працює ✅
- [x] Обмежити SG тільки на Cloudflare IP ranges (80/443) + ваш IP (22) ✅
- [x] Додати resource limits та liveness/readiness probes до portfolio deployment ✅
- [ ] Деплой `llm-api` (Windows → AWS не переносимо, llama-server залишається локально)
- [ ] Перевести Terraform state в S3 (MinIO)
- [ ] Налаштувати backup etcd
- [ ] CrowdSec на AWS K3s
- [ ] Перевірити AWS billing dashboard

---

## 12. Важливі нотатки (Important)

- **Важливо:** Не зупиняйте EC2-інстанс без попереднього розв'язку EIP — інакше платитимете $0.005/год за незакріплений EIP.
- **Важливо:** AWS Free Tier t3.micro доступний, поки не вичерпано ліміт 750 год/міс. Моніторте через AWS Billing Dashboard.
- **Важливо:** Ніколи не фіксуйте AWS-ключі в git. Використовуйте `.gitignore` та перевіряйте історію перед push.
- **Важливо:** kubectl з Windows — переконайтеся, що `KUBECONFIG` вказує на `config-aws` з сервером `13.49.255.149:6443`.
- **Важливо:** Klipper-lb балансер працює тільки з приватним IP EC2 (`172.31.39.148`). Не змінюйте `loadBalancerIP` на публічний EIP.
- **Важливо:** Після змін у security group тестуйте SSH з'єднання з вашої IP, щоб не заблокувати собі доступ.
- **Важливо:** Deployment portfolio тепер має resource limits (cpu:100m/50m, memory:128Mi/64Mi) та liveness/readiness probes.
- **Важливо:** Перевіряйте, що `certificate portfolio-tls` у стані `Ready=True` перед використанням HTTPS.
