# Dashboard Creator MD

> **Призначення:** Посібник зі створення, імпорту та редагування дашбордів Grafana для проекту SysOps → DevOps.  
> **Середовище:** Локальний стек Docker Compose на Linux-сервері (192.168.100.203) — Prometheus + Grafana + node-exporter.  
> **Порти:** Grafana — `:3000`, Prometheus — `:9091`

---

## 0. Безпека: секрети та паролі

Всі паролі, ключі та чутливі дані **винесені у файл `.env`**, який доданий до `.gitignore` і ніколи не потрапляє в Git.

### 0.1 Файли з секретами

| Файл | Призначення | В Git? |
|------|-----------|--------|
| `.env` | Реальні паролі та ключі | **НІ** (`.gitignore`) |
| `.env.example` | Шаблон для клонування проекту | ТАК |
| `ansible/group_vars/devops_lab.yml` | Читає `GRAFANA_PASSWORD` із середовища | ТАК (сирий пароль не зберігається) |
| `docker/monitoring/docker-compose.yml` | Використовує `${GRAFANA_PASSWORD:-devops123}` | ТАК |
| `scripts/grafana-sync.py` | Default `devops123`, читає з env | ТАК |

### 0.2 Як використовувати

```bash
# 1. Скопіюйте шаблон
cp .env.example .env

# 2. Замініть значення на свої
nano .env

# 3. Завантажте змінні в shell
source .env
```

### 0.3 Що робити, якщо пароль випадково потрапив у Git

```bash
# 1. Негайно змініть пароль у всіх системах
# 2. Використовуйте git filter-repo або BFG Repo-Cleaner для видалення з історії
# 3. Форсируйте push с --force
```

---

## 1. Архітектура моніторингу

```
Grafana (localhost:3000)
  │
  ├── Data Source: Prometheus (http://prometheus:9090)
  │     │
  │     ├── job=node-exporter       → локальний хост (Linux сервер 192.168.100.203)
  │     ├── job=aws-node-exporter   → AWS EC2 через SSH tunnel (порт 9101)
  │     ├── job=prometheus          → метрики самого Prometheus
  │     ├── job=llama-server        → LLM inference на Windows (192.168.100.15:8080)
  │     └── job=llm-api             → FastAPI proxy на Linux (192.168.100.203:30800)
  │
  └── Data Source: Alertmanager (опционально)
```

---

## 2. Створення дашборда з нуля

### 2.1 Вхід у Grafana

```
URL:      http://192.168.100.203:3000
Login:    admin
Password: devops123 (або заданий у змінній GRAFANA_PASSWORD)
```

### 2.2 Створення нового дашборда

1. **Dashboard → New → New Dashboard**
2. **Add visualization**
3. Виберіть **Prometheus** як Data Source
4. Введіть PromQL-запит у поле **Metrics browser / Code**

### 2.3 Базові PromQL-запити

| Що хочемо побачити | PromQL |
|-------------------|--------|
| Загрузка CPU (1 мин) | `node_load1{instance=~"$instance"}` |
| Всего памяти | `node_memory_MemTotal_bytes{instance=~"$instance"}` |
| Доступно памяти | `node_memory_MemAvailable_bytes{instance=~"$instance"}` |
| Использование swap | `node_memory_SwapTotal_bytes{instance=~"$instance"} - node_memory_SwapFree_bytes{instance=~"$instance"}` |
| Использование диска / | `100 - (node_filesystem_avail_bytes{mountpoint="/", instance=~"$instance"} / node_filesystem_size_bytes{mountpoint="/", instance=~"$instance"} * 100)` |
| Network received | `rate(node_network_receive_bytes_total{instance=~"$instance", device!="lo"}[5m])` |
| Network transmitted | `rate(node_network_transmit_bytes_total{instance=~"$instance", device!="lo"}[5m])` |

### 2.4 Типи панелей

| Тип | Коли використовувати |
|-----|-------------------|
| **Stat** | Одне значення (memory total, CPU cores) |
| **Time series** | Зміна в часі (CPU load, memory, network) |
| **Gauge** | Відсоткове значення (disk usage, memory usage %) |
| **Table** | Список (top процесів за пам'яттю) |
| **Bar gauge** | Порівняння між кількома сутностями |
| **Pie chart** | Розподіл часток |

---

## 3. Імпорт готового дашборда

### 3.1 Через UI Grafana

1. **Dashboard → New → Import**
2. Завантажте JSON-файл або вставте вміст JSON
3. Виберіть Data Source: **Prometheus**
4. Нажміть **Import**

### 3.2 Через API (автоматизація)

```bash
# Импорт дашборда через Grafana API
curl -X POST http://admin:devops123@192.168.100.203:3000/api/dashboards/db \
  -H "Content-Type: application/json" \
  -d '{
    "dashboard": {
      "title": "My Dashboard",
      "panels": [],
      "time": {"from": "now-1h", "to": "now"}
    },
    "overwrite": true
  }'
```

### 3.3 Перевірка імпорту

```bash
# Отримати список усіх дашбордів
curl -s http://admin:devops123@192.168.100.203:3000/api/search?type=dash-db \
  | python3 -m json.tool
```

---

## 4. Робота зі змінними (template variables)

Змінні дозволяють перемикати джерело даних у панелях без редагування кожного запиту.

### 4.1 Додавання змінної

1. У дашборді: **Settings → Variables → Add variable**
2. Тип: **Query**
3. Name: `instance`
4. Label: `Instance`
5. Query: `label_values(node_load1, instance)`
6. Multi-value: ✅
7. Include All option: ✅
8. Save

### 4.2 Використання змінної в PromQL

```
node_memory_MemTotal_bytes{instance=~"$instance"}
```

### 4.3 Фільтрація за допомогою regex

```
# Фільтр instance за двома jobs:
# node-exporter (локальний) + aws-node-exporter (AWS через тунель)
instance=~".*(observability|9101).*"
```

### 4.4 Де взяти правильні мітки

```bash
# Перегляд усіх доступних instance label значень
curl -s http://localhost:9091/api/v1/label/instance/values | python3 -m json.tool

# Або через Prometheus UI: http://192.168.100.203:9091/classic/targets
```

---

## 5. Job-и Prometheus у проекті

| Job name | Targets | Опис |
|----------|---------|----------|
| `prometheus` | `localhost:9090` | Сам Prometheus |
| `node-exporter` | `node-exporter:9100` | Локальний Linux-сервер (192.168.100.203) |
| `aws-node-exporter` | `172.17.0.1:9101` | AWS EC2 через SSH tunnel |
| `llama-server` | `192.168.100.15:8080` | LLM inference на Windows |
| `llm-api` | `192.168.100.203:30800` | FastAPI proxy |

---

## 6. Редагування існуючого дашборда

### 6.1 Через UI

1. Відкрийте дашборд → **Dashboard settings** (шестерня)
2. Змініть:
   - **Panels** — клік на заголовок панелі → Edit
   - **Variables** — Settings → Variables
   - **Time range** — кнопка часу в правому верхньому куті
3. Збережіть: **Save** (або Ctrl+S)

### 6.2 Експорт JSON для редагування у файлі

```bash
# Через API — отримати JSON дашборду
curl -s http://admin:devops123@192.168.100.203:3000/api/dashboards/uid/aws-k3s-system \
  | python3 -m json.tool > dashboard-backup.json
```

### 6.3 Редагування JSON вручну

```bash
# Локальні файли дашбордів у проекті
ls -la docker/monitoring/grafana-*.json
# → grafana-aws-dashboard.json
# → grafana-aws-ec2.json
# → grafana-llm-dashboard.json

# Відредагувати, потім імпортувати заново
nano docker/monitoring/grafana-aws-dashboard.json
```

### 6.4 Перевірка змін

```bash
# Після імпорту — перевірити, що панелі показують дані
# 1. Открыть дашборд в браузере
# 2. Проверить каждую панель на наличие данных
# 3. Если панель показывает "No data" — проверить:
#    - Есть ли target instance в Prometheus (http://192.168.100.203:9091/targets)
#    - Правильно ли работает SSH tunnel
#    - Чи правильно відфільтровані мітки
```

---

## 7. Діагностика проблем з дашбордом

### 7.1 Панель показує "No data" або нулі

| Можлива причина | Як перевірити | Як виправити |
|-------------------|---------------|---------------|
| Мітка instance не збігається | `curl http://localhost:9091/api/v1/label/instance/values` | Оновити regex-фільтр у запиті |
| SSH tunnel не працює | `curl http://localhost:9101/metrics \| head -5` | Перезапустити aws-tunnel.sh |
| Target не scraпиться | http://192.168.100.203:9091/targets | Перевірити Prometheus job config |
| Метрика не існує | `curl http://localhost:9091/api/v1/query?query=node_memory_MemTotal_bytes` | Уточнити ім'я метрики |
| Немає даних за вибраний період | Переключити time range на `now-30m` | Зачекати збору даних |

### 7.2 SSH tunnel неактивний

```bash
# На Linux-сервере (192.168.100.203)
# Проверка
ps aux | grep "9101:172.31.39.148:9100"

# Перезапуск
pkill -f "9101:172.31.39.148:9100"
bash /root/scripts/aws-tunnel.sh

# Або через systemd (якщо налаштовано)
systemctl status aws-tunnel
systemctl restart aws-tunnel
```

### 7.3 Target недоступний у Prometheus

```bash
# Проверка targets
curl -s http://localhost:9091/api/v1/targets | python3 -m json.tool

# Проверка конкретного job
curl -s 'http://localhost:9091/api/v1/query?query=up{job="aws-node-exporter"}' \
  | python3 -m json.tool
```

---

## 8. Практичний приклад: дашборд для AWS EC2

Створено окремий дашборд **«AWS EC2 — System»** (`grafana-aws-ec2.json`, uid: `aws-ec2-system`), який показує **тільки AWS EC2** через job=`aws-node-exporter`.

### 8.1 Що він містить

| Ряд | Панелі |
|-----|--------|
| **y=0** | Uptime, Memory Total, Memory Available, Swap Used, Memory Usage %, CPU Cores |
| **y=3** | CPU Load (1m/5m/15m), Disk Usage (/), Disk Usage (/var/lib/kubelet) |
| **y=6** | CPU Usage % by mode, CPU Load timeseries |
| **y=12** | Memory Usage (6 метрик), Swap Usage |
| **y=18** | Disk Usage % all mounts, Disk I/O read/write |
| **y=24** | Network Traffic (bps), Network Errors |
| **y=30** | Network Packets, Processes (Max/Running/Blocked) |
| **y=33-41** | Context Switches, Entropy, Filesystem inodes, TCP Connections, UDP Sockets, Memory Trend 7d |

### 8.2 Імпорт

```bash
python3 scripts/grafana-sync.py import --file grafana-aws-ec2.json
```

Або через UI: **Dashboard → New → Import → завантажити файл**

### 8.3 Два дашборди AWS у проекті

| Дашборд | Файл | UID | Що показує |
|---------|------|-----|---------------|
| **AWS EC2 — System** | `grafana-aws-ec2.json` | `aws-ec2-system` | Тільки AWS EC2 (job=`aws-node-exporter`) |
| **AWS K3s — System** | `grafana-aws-dashboard.json` | `aws-k3s-system` | Обидва хости (локальний + AWS) через змінну `$instance` |

---

## 9. Структура JSON дашборда

```json
{
  "title": "Название дашборда",
  "uid": "уникальный-id",
  "tags": ["tag1", "tag2"],
  "timezone": "browser",
  "editable": true,
  "panels": [
    {
      "id": 1,
      "title": "Название панели",
      "type": "stat",
      "gridPos": {"x": 0, "y": 0, "w": 4, "h": 3},
      "targets": [
        {
          "expr": "PromQL запрос",
          "legendFormat": "Легенда",
          "instant": false
        }
      ]
    }
  ],
  "templating": {
    "list": [
      {
        "name": "instance",
        "type": "query",
        "query": "label_values(up, instance)",
        "refresh": 1,
        "includeAll": true,
        "multi": true
      }
    ]
  },
  "refresh": "30s",
  "time": {"from": "now-1h", "to": "now"}
}
```

| Поле | Опис |
|------|----------|
| `title` | Відображувана назва |
| `uid` | Унікальний ID для API (одного разу заданий — не змінювати) |
| `panels[].type` | Тип візуалізації (`stat`, `timeseries`, `gauge`, `table`) |
| `gridPos` | Позиція на сітці (x,y,w,h) — 24 колонки |
| `targets[].expr` | PromQL-запит |
| `templating.list` | Змінні дашборда |
| `refresh` | Автооновлення (наприклад `30s`) |

---

## 10. Автоматизація через скрипт

Всі операції з дашбордами виконуються через єдиний скрипт `scripts/grafana-sync.py`.

### 10.1 Встановлення

```bash
# На Linux-сервере (192.168.100.203)
pip3 install requests
```

### 10.2 Команди

```bash
# Перевірити доступність Grafana
python3 scripts/grafana-sync.py health

# Імпортувати ВСІ дашборди з docker/monitoring/
python3 scripts/grafana-sync.py import

# Импортировать один конкретный дашборд
python3 scripts/grafana-sync.py import --file grafana-aws-ec2.json

# Экспортировать ВСЕ дашборды из Grafana в файлы
python3 scripts/grafana-sync.py export

# Экспортировать один дашборд по UID
python3 scripts/grafana-sync.py export --uid aws-ec2-system

# Показать список дашбордов в Grafana
python3 scripts/grafana-sync.py list
```

### 10.3 Змінні середовища (якщо параметри відрізняються від стандартних)

```bash
export GRAFANA_URL=http://192.168.100.203:3000
export GRAFANA_USER=admin
export GRAFANA_PASSWORD=devops123
export DASHBOARDS_DIR=/home/user/mydashboards
```

### 10.4 Приклад робочого процесу

```bash
# 1. Редактируем JSON-файл дашборда
nano docker/monitoring/grafana-aws-ec2.json

# 2. Импортируем изменения в Grafana
python3 scripts/grafana-sync.py import --file grafana-aws-ec2.json

# 3. Проверяем, что применилось
python3 scripts/grafana-sync.py list

# 4. Открываем в браузере: http://192.168.100.203:3000
```

---

## 11. Деплой на Linux-сервер

### 11.1 Підключення

Сервер доступний за SSH-аліасом `devops-lab` (із `~/.ssh/config`):
- Host: `192.168.100.203`
- Port: `7927`
- User: `tst`
- Key: `~/.ssh/devops_lab`

### 11.2 Розгортання дашбордів

```bash
# 1. Скопировать файлы на сервер
scp -P 7927 scripts/grafana-sync.py docker/monitoring/grafana-*.json tst@192.168.100.203:/tmp/

# 2. Подключиться и установить зависимости (если нет)
ssh devops-lab 'pip3 install requests'

# 3. Импортировать/экспортировать через скрипт
ssh devops-lab 'python3 /tmp/grafana-sync.py import --file /tmp/grafana-aws-ec2.json'
ssh devops-lab 'python3 /tmp/grafana-sync.py import --file /tmp/grafana-aws-dashboard.json'

# 4. Удалить временные файлы
ssh devops-lab 'rm /tmp/grafana-sync.py /tmp/grafana-aws-ec2.json /tmp/grafana-aws-dashboard.json'
```

### 11.3 Поточні дашборди в Grafana

| UID | Title |
|-----|-------|
| `aws-ec2-system` | AWS EC2 — System |
| `aws-k3s-system` | AWS K3s — System |
| `8ecc8a5f-1c0c-4bb2-8395-e31a1cacbc54` | LLM API — Qwen3-35B on RTX 3050 |
| `rYdddlPWk` | Node Exporter Full |

---

## 12. Швидкі команди

```bash
# Перевірити всі instance labels
curl -s http://localhost:9091/api/v1/label/instance/values | python3 -m json.tool

# Перевірити job labels
curl -s http://localhost:9091/api/v1/label/job/values | python3 -m json.tool

# Перевірити всі active targets
curl -s http://localhost:9091/api/v1/targets | python3 -c "import sys,json; data=json.load(sys.stdin); [print(f'{t[\"labels\"][\"job\"]}: {t[\"labels\"][\"instance\"]} UP={t[\"health\"]}') for t in data['data']['activeTargets']]"

# Виконати довільний PromQL запит
curl -s 'http://localhost:9091/api/v1/query?query=up{job="aws-node-exporter"}' \
  | python3 -m json.tool
```

---

## 13. Посилання

- [Grafana Dashboards API](https://grafana.com/docs/grafana/latest/developers/http_api/dashboard/)
- [PromQL Cheat Sheet](https://promlabs.com/promql-cheat-sheet/)
- [Локальний стек моніторингу](../docker/monitoring/docker-compose.yml)
- [Prometheus config](../docker/monitoring/prometheus.yml)
- [Дашборд AWS K3s — System](../docker/monitoring/grafana-aws-dashboard.json)
- [Дашборд AWS EC2 — System](../docker/monitoring/grafana-aws-ec2.json)
- [Дашборд LLM API](../docker/monitoring/grafana-llm-dashboard.json)
- [aws-tunnel.sh](../scripts/aws-tunnel.sh)
- [Отчёт о диагностике](CheckAndRepare.md)
