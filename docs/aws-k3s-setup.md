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

## 8. Наступні кроки

- [ ] Деплой `llm-api` через ArgoCD
- [ ] Перевести Terraform state в S3 (MinIO)
- [ ] Налаштувати backup etcd
- [ ] Додати Cloudflare DNS / proxy
- [ ] Перевірити AWS billing dashboard
