# System Startup Checklist

## 1. Ubuntu Server (Linux)

```bash
# Docker containers
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# K3s cluster
kubectl get nodes
kubectl get pods -A | grep -v Running | grep -v Completed

# Ports open
ss -tlnp | grep -E "9000|9091|3000|9100|9002|6443"

# ArgoCD apps
kubectl get app -n argocd

# Certificates
kubectl get certificate -n default

# LLM API pod
kubectl get pods -l app=llm-api
```

**Очікуваний результат:**
---

## 2. Windows (llama-server)

```powershell
# Перевірка чи запущений
Get-Process llama-server -ErrorAction SilentlyContinue | Select-Object Name, CPU, WorkingSet

# Перевірка порту
netstat -an | findstr "8080"

# Тест API
curl http://localhost:8080/health
curl http://localhost:8080/v1/models
```

**Якщо не запущений — стартуємо:**
```powershell
cd J:\llm_working_bin\llama-b9159-bin-win-cuda-12.4-x64
.\llama-server.exe -m "l:\LLM\models\Qwen3.6-35B-A3B-MXFP4_MOE.gguf" -fa 1 -ngl 99 -ncmoe 32 -ub 1024 -b 1024 -t 12 -ctk q8_0 -ctv q8_0 --jinja --host 0.0.0.0 --port 8080 --metrics
```

---

## 3. Зовнішній доступ

```bash
curl https://ai-devops.pp.ua/
curl https://llm.ai-devops.pp.ua/health

export API_KEY=821ac427ce52799484ae5d127b1d0565e9ed05cd86fb2979f07e9a19904bb13c
curl -X POST https://llm.ai-devops.pp.ua/v1/chat \
  -H "Content-Type: application/json" \
  -H "X-API-Key: $API_KEY" \
  -d '{"message":"ping","max_tokens":5}'

curl -s http://192.168.100.203:9091/api/v1/targets | python3 -m json.tool | grep -E "job|health"
```

---

## 4. Якщо щось не так

### Docker контейнери впали
Все що з ```bash виконується в терміналі з підключенням до хоста 192.168.100.203 командою ssh devops-lab
```bash
cd ~/repo/docker/monitoring && docker compose up -d
cd ~/repo/docker/portainer && docker compose up -d
```

### K3s pod не запускається
```bash
kubectl describe pod -l app=llm-api -n default | tail -20
kubectl rollout restart deployment/llm-api -n default
```

### ArgoCD out of sync
```bash
kubectl -n argocd patch app llm-api --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'
```

### Сертифікат не оновився
```bash
kubectl delete certificate llm-api-tls -n default
sleep 30
kubectl get certificate -n default -w
```

### llama-server недоступний з Ubuntu
```bash
curl -v http://192.168.100.15:8080/health
# PowerShell (admin): New-NetFirewallRule -DisplayName "llama-server" -Direction Inbound -Protocol TCP -LocalPort 8080 -Action Allow
```

---

## 5. CrowdSec статус

```bash
sudo cscli alerts list
sudo cscli decisions list
sudo cscli metrics | grep -A10 "Acquisition"
```

---

## 6. Повний тест suite

```bash
export API_KEY=821ac427ce52799484ae5d127b1d0565e9ed05cd86fb2979f07e9a19904bb13c
bash ~/repo/llm-api/tests/test_api.sh https://llm.ai-devops.pp.ua
# Очікується: 6/6 passed
```
