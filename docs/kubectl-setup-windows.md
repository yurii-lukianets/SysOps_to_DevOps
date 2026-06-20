# Налаштування kubectl на Windows для керування Kubernetes-кластером

## Дата виконання: 01.06.2026

---

## Мета
Налаштувати керування Kubernetes-кластером (K3s) з Windows-машини через kubectl без необхідності постійного SSH-доступу.

---

## Виконані кроки

### Крок 1: Перевірка встановлення kubectl на Windows
**Команда:**
```powershell
where.exe kubectl
```
**Результат:** kubectl встановлено через Winget за шляхом:
`C:\Users\LUKAS\AppData\Local\Microsoft\WinGet\Packages\Kubernetes.kubectl_Microsoft.Winget.Source_8wekyb3d8bbwe\kubectl.exe`

### Крок 2: Перевірка версії клієнта
**Команда:**
```powershell
kubectl version --client
```
**Результат:**
- Client Version: v1.36.1
- Kustomize Version: v5.8.1

### Крок 3: Перевірка наявності конфігу
**Команда:**
```powershell
Test-Path "$env:USERPROFILE\.kube\config"
```
**Результат:** Конфіг відсутній.

### Крок 4: Копіювання конфігу з Linux-сервера
**Проблема:** Пряме копіювання через scp не працює через права доступу до `/etc/rancher/k3s/k3s.yaml`.

**Рішення:** Використати SSH для читання файлу та перенаправлення в локальну папку.

**Команда:**
```powershell
ssh devops-lab "cat ~/.kube/config" | Out-File -FilePath "$env:USERPROFILE\.kube\config" -Encoding utf8
```
**Результат:** Конфіг успішно скопійовано з `~/.kube/config` на сервері.

### Крок 5: Заміна IP-адреси в конфігу
**Проблема:** Скопійований конфіг містить `127.0.0.1`, але з Windows потрібно звертатися до IP сервера `192.168.100.203`.

**Команда:**
```powershell
(Get-Content "$env:USERPROFILE\.kube\config") | ForEach-Object { $_ -replace "127.0.0.1", "192.168.100.203" } | Set-Content "$env:USERPROFILE\.kube\config"
```
**Результат:** IP замінено на `192.168.100.203`.

### Крок 6: Перевірка підключення до кластеру
**Команда:**
```powershell
kubectl cluster-info
```
**Результат:**
- Kubernetes control plane is running at https://192.168.100.203:
