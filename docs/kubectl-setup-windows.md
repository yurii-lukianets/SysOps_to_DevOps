# Настройка kubectl на Windows для управления Kubernetes-кластером

## Дата выполнения: 01.06.2026

---

## Цель
Настроить управление Kubernetes-кластером (K3s) с Windows-машины через kubectl без необходимости постоянного SSH-доступа.

---

## Выполненные шаги

### Шаг 1: Проверка установки kubectl на Windows
**Команда:**
```powershell
where.exe kubectl
```
**Результат:** kubectl установлен через Winget по пути:
`C:\Users\LUKAS\AppData\Local\Microsoft\WinGet\Packages\Kubernetes.kubectl_Microsoft.Winget.Source_8wekyb3d8bbwe\kubectl.exe`

### Шаг 2: Проверка версии клиента
**Команда:**
```powershell
kubectl version --client
```
**Результат:**
- Client Version: v1.36.1
- Kustomize Version: v5.8.1

### Шаг 3: Проверка наличия конфига
**Команда:**
```powershell
Test-Path "$env:USERPROFILE\.kube\config"
```
**Результат:** Конфиг отсутствует.

### Шаг 4: Копирование конфига с Linux-сервера
**Проблема:** Прямое копирование через scp не работает из-за прав доступа к `/etc/rancher/k3s/k3s.yaml`.

**Решение:** Использовать SSH для чтения файла и перенаправления в локальную папку.

**Команда:**
```powershell
ssh devops-lab "cat ~/.kube/config" | Out-File -FilePath "$env:USERPROFILE\.kube\config" -Encoding utf8
```
**Результат:** Конфиг успешно скопирован из `~/.kube/config` на сервере.

### Шаг 5: Замена IP-адреса в конфиге
**Проблема:** Скопированный конфиг содержит `127.0.0.1`, но с Windows нужно обращаться к IP сервера `192.168.100.203`.

**Команда:**
```powershell
(Get-Content "$env:USERPROFILE\.kube\config") | ForEach-Object { $_ -replace "127.0.0.1", "192.168.100.203" } | Set-Content "$env:USERPROFILE\.kube\config"
```
**Результат:** IP заменён на `192.168.100.203`.

### Шаг 6: Проверка подключения к кластеру
**Команда:**
```powershell
kubectl cluster-info
```
**Результат:**
- Kubernetes control plane is running at https://192.168.100.203: