# Dashboard Creator MD

> **Назначение:** Руководство по созданию, импорту и редактированию дашбордов Grafana для проекта SysOps → DevOps.  
> **Окружение:** Локальный стек Docker Compose на Linux-сервере (192.168.100.203) — Prometheus + Grafana + node-exporter.  
> **Порты:** Grafana — `:3000`, Prometheus — `:9091`

---

## 0. Безопасность: секреты и пароли

Все пароли, ключи и чувствительные данные **вынесены в файл `.env`**, который добавлен в `.gitignore` и никогда не попадает в Git.

### 0.1 Файлы с секретами

| Файл | Назначение | В Git? |
|------|-----------|--------|
| `.env` | Реальные пароли и ключи | **НЕТ** (`.gitignore`) |
| `.env.example` | Шаблон для клонирования проекта | ДА |
| `ansible/group_vars/devops_lab.yml` | Читает `GRAFANA_PASSWORD` из окружения | ДА (сырой пароль не хранится) |
| `docker/monitoring/docker-compose.yml` | Использует `${GRAFANA_PASSWORD:-devops123}` | ДА |
| `scripts/grafana-sync.py` | Default `devops123`, читает из env | ДА |

### 0.2 Как использовать

```bash
# 1. Скопируйте шаблон
cp .env.example .env

# 2. Замените значения на свои
nano .env

# 3. Загрузите переменные в shell
source .env
```

### 0.3 Что делать, если пароль случайно попал в Git

```bash
# 1. Немедленно смените пароль во всех системах
# 2. Используйте git filter-repo или BFG Repo-Cleaner для удаления из истории
# 3. Форсируйте push с --force
```

---

## 1. Архитектура мониторинга

```
Grafana (localhost:3000)
  │
  ├── Data Source: Prometheus (http://prometheus:9090)
  │     │
  │     ├── job=node-exporter       → локальный хост (Linux сервер 192.168.100.203)
  │     ├── job=aws-node-exporter   → AWS EC2 через SSH tunnel (порт 9101)
  │     ├── job=prometheus          → метрики самого Prometheus
  │     ├── job=llama-server        → LLM inference на Windows (192.168.100.15:8080)
  │     └── job=llm-api             → FastAPI proxy на Linux (192.168.100.203:30800)
  │
  └── Data Source: Alertmanager (опционально)
```

---

## 2. Создание дашборда с нуля

### 2.1 Вход в Grafana

```
URL:      http://192.168.100.203:3000
Login:    admin
Password: devops123 (или задан в переменной GRAFANA_PASSWORD)
```

### 2.2 Создание нового дашборда

1. **Dashboard → New → New Dashboard**
2. **Add visualization**
3. Выберите **Prometheus** как Data Source
4. Введите PromQL-запрос в поле **Metrics browser / Code**

### 2.3 Базовые PromQL-запросы

| Что хотим увидеть | PromQL |
|-------------------|--------|
| Загрузка CPU (1 мин) | `node_load1{instance=~"$instance"}` |
| Всего памяти | `node_memory_MemTotal_bytes{instance=~"$instance"}` |
| Доступно памяти | `node_memory_MemAvailable_bytes{instance=~"$instance"}` |
| Использование swap | `node_memory_SwapTotal_bytes{instance=~"$instance"} - node_memory_SwapFree_bytes{instance=~"$instance"}` |
| Использование диска / | `100 - (node_filesystem_avail_bytes{mountpoint="/", instance=~"$instance"} / node_filesystem_size_bytes{mountpoint="/", instance=~"$instance"} * 100)` |
| Network received | `rate(node_network_receive_bytes_total{instance=~"$instance", device!="lo"}[5m])` |
| Network transmitted | `rate(node_network_transmit_bytes_total{instance=~"$instance", device!="lo"}[5m])` |

### 2.4 Типы панелей

| Тип | Когда использовать |
|-----|-------------------|
| **Stat** | Одно значение (memory total, CPU cores) |
| **Time series** | Изменение во времени (CPU load, memory, network) |
| **Gauge** | Процентное значение (disk usage, memory usage %) |
| **Table** | Список (top процессов по памяти) |
| **Bar gauge** | Сравнение между несколькими сущностями |
| **Pie chart** | Распределение долей |

---

## 3. Импорт готового дашборда

### 3.1 Через UI Grafana

1. **Dashboard → New → Import**
2. Загрузите JSON-файл или вставьте содержимое JSON
3. Выберите Data Source: **Prometheus**
4. Нажмите **Import**

### 3.2 Через API (автоматизация)

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

### 3.3 Проверка импорта

```bash
# Получить список всех дашбордов
curl -s http://admin:devops123@192.168.100.203:3000/api/search?type=dash-db \
  | python3 -m json.tool
```

---

## 4. Работа с переменными (template variables)

Переменные позволяют переключать источник данных в панелях без редактирования каждого запроса.

### 4.1 Добавление переменной

1. В дашборде: **Settings → Variables → Add variable**
2. Тип: **Query**
3. Name: `instance`
4. Label: `Instance`
5. Query: `label_values(node_load1, instance)`
6. Multi-value: ✅
7. Include All option: ✅
8. Save

### 4.2 Использование переменной в PromQL

```
node_memory_MemTotal_bytes{instance=~"$instance"}
```

### 4.3 Фильтрация с помощью regex

```
# Фильтр instance по двум jobs:
# node-exporter (локальный) + aws-node-exporter (AWS через туннель)
instance=~".*(observability|9101).*"
```

### 4.4 Где взять правильные метки

```bash
# Просмотр всех доступных instance label значений
curl -s http://localhost:9091/api/v1/label/instance/values | python3 -m json.tool

# Или через Prometheus UI: http://192.168.100.203:9091/classic/targets
```

---

## 5. Job-ы Prometheus в проекте

| Job name | Targets | Описание |
|----------|---------|----------|
| `prometheus` | `localhost:9090` | Сам Prometheus |
| `node-exporter` | `node-exporter:9100` | Локальный Linux-сервер (192.168.100.203) |
| `aws-node-exporter` | `172.17.0.1:9101` | AWS EC2 через SSH tunnel |
| `llama-server` | `192.168.100.15:8080` | LLM inference на Windows |
| `llm-api` | `192.168.100.203:30800` | FastAPI proxy |

---

## 6. Редактирование существующего дашборда

### 6.1 Через UI

1. Откройте дашборд → **Dashboard settings** (шестерёнка)
2. Измените:
   - **Panels** — клик на заголовок панели → Edit
   - **Variables** — Settings → Variables
   - **Time range** — кнопка времени в правом верхнем углу
3. Сохраните: **Save** (или Ctrl+S)

### 6.2 Экспорт JSON для редактирования в файле

```bash
# Через API — получить JSON дашборда
curl -s http://admin:devops123@192.168.100.203:3000/api/dashboards/uid/aws-k3s-system \
  | python3 -m json.tool > dashboard-backup.json
```

### 6.3 Редактирование JSON вручную

```bash
# Локальные файлы дашбордов в проекте
ls -la docker/monitoring/grafana-*.json
# → grafana-aws-dashboard.json
# → grafana-aws-ec2.json
# → grafana-llm-dashboard.json

# Отредактировать, затем импортировать заново
nano docker/monitoring/grafana-aws-dashboard.json
```

### 6.4 Проверка изменений

```bash
# После импорта — проверить, что панели показывают данные
# 1. Открыть дашборд в браузере
# 2. Проверить каждую панель на наличие данных
# 3. Если панель показывает "No data" — проверить:
#    - Есть ли target instance в Prometheus (http://192.168.100.203:9091/targets)
#    - Правильно ли работает SSH tunnel
#    - Правильно ли отфильтрованы метки
```

---

## 7. Диагностика проблем с дашбордом

### 7.1 Панель показывает "No data" или нули

| Возможная причина | Как проверить | Как исправить |
|-------------------|---------------|---------------|
| Метка instance не совпадает | `curl http://localhost:9091/api/v1/label/instance/values` | Обновить regex-фильтр в запросе |
| SSH tunnel не работает | `curl http://localhost:9101/metrics \| head -5` | Перезапустить aws-tunnel.sh |
| Target не scraпится | http://192.168.100.203:9091/targets | Проверить Prometheus job config |
| Метрика не существует | `curl http://localhost:9091/api/v1/query?query=node_memory_MemTotal_bytes` | Уточнить имя метрики |
| Нет данных за выбранный период | Переключить time range на `now-30m` | Подождать сбора данных |

### 7.2 SSH tunnel неактивен

```bash
# На Linux-сервере (192.168.100.203)
# Проверка
ps aux | grep "9101:172.31.39.148:9100"

# Перезапуск
pkill -f "9101:172.31.39.148:9100"
bash /root/scripts/aws-tunnel.sh

# Или через systemd (если настроен)
systemctl status aws-tunnel
systemctl restart aws-tunnel
```

### 7.3 Target недоступен в Prometheus

```bash
# Проверка targets
curl -s http://localhost:9091/api/v1/targets | python3 -m json.tool

# Проверка конкретного job
curl -s 'http://localhost:9091/api/v1/query?query=up{job="aws-node-exporter"}' \
  | python3 -m json.tool
```

---

## 8. Практический пример: дашборд для AWS EC2

Создан отдельный дашборд **«AWS EC2 — System»** (`grafana-aws-ec2.json`, uid: `aws-ec2-system`), который показывает **только AWS EC2** через job=`aws-node-exporter`.

### 8.1 Что он содержит

| Ряд | Панели |
|-----|--------|
| **y=0** | Uptime, Memory Total, Memory Available, Swap Used, Memory Usage %, CPU Cores |
| **y=3** | CPU Load (1m/5m/15m), Disk Usage (/), Disk Usage (/var/lib/kubelet) |
| **y=6** | CPU Usage % by mode, CPU Load timeseries |
| **y=12** | Memory Usage (6 метрик), Swap Usage |
| **y=18** | Disk Usage % all mounts, Disk I/O read/write |
| **y=24** | Network Traffic (bps), Network Errors |
| **y=30** | Network Packets, Processes (Max/Running/Blocked) |
| **y=33-41** | Context Switches, Entropy, Filesystem inodes, TCP Connections, UDP Sockets, Memory Trend 7d |

### 8.2 Импорт

```bash
python3 scripts/grafana-sync.py import --file grafana-aws-ec2.json
```

Или через UI: **Dashboard → New → Import → загрузить файл**

### 8.3 Два дашборда AWS в проекте

| Дашборд | Файл | UID | Что показывает |
|---------|------|-----|---------------|
| **AWS EC2 — System** | `grafana-aws-ec2.json` | `aws-ec2-system` | Только AWS EC2 (job=`aws-node-exporter`) |
| **AWS K3s — System** | `grafana-aws-dashboard.json` | `aws-k3s-system` | Оба хоста (локальный + AWS) через переменную `$instance` |

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

| Поле | Описание |
|------|----------|
| `title` | Отображаемое название |
| `uid` | Уникальный ID для API (однажды задан — не менять) |
| `panels[].type` | Тип визуализации (`stat`, `timeseries`, `gauge`, `table`) |
| `gridPos` | Позиция на сетке (x,y,w,h) — 24 колонки |
| `targets[].expr` | PromQL-запрос |
| `templating.list` | Переменные дашборда |
| `refresh` | Автообновление (например `30s`) |

---

## 10. Автоматизация через скрипт

Все операции с дашбордами выполняются через единый скрипт `scripts/grafana-sync.py`.

### 10.1 Установка

```bash
# На Linux-сервере (192.168.100.203)
pip3 install requests
```

### 10.2 Команды

```bash
# Проверить доступность Grafana
python3 scripts/grafana-sync.py health

# Импортировать ВСЕ дашборды из docker/monitoring/
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

### 10.3 Переменные окружения (если параметры отличаются от дефолтных)

```bash
export GRAFANA_URL=http://192.168.100.203:3000
export GRAFANA_USER=admin
export GRAFANA_PASSWORD=devops123
export DASHBOARDS_DIR=/home/user/mydashboards
```

### 10.4 Пример рабочего процесса

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

### 11.1 Подключение

Сервер доступен по SSH-алиасу `devops-lab` (из `~/.ssh/config`):
- Host: `192.168.100.203`
- Port: `7927`
- User: `tst`
- Key: `~/.ssh/devops_lab`

### 11.2 Развёртывание дашбордов

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

### 11.3 Текущие дашборды в Grafana

| UID | Title |
|-----|-------|
| `aws-ec2-system` | AWS EC2 — System |
| `aws-k3s-system` | AWS K3s — System |
| `8ecc8a5f-1c0c-4bb2-8395-e31a1cacbc54` | LLM API — Qwen3-35B on RTX 3050 |
| `rYdddlPWk` | Node Exporter Full |

---

## 12. Быстрые команды

```bash
# Проверить все instance labels
curl -s http://localhost:9091/api/v1/label/instance/values | python3 -m json.tool

# Проверить job labels
curl -s http://localhost:9091/api/v1/label/job/values | python3 -m json.tool

# Проверить все active targets
curl -s http://localhost:9091/api/v1/targets | python3 -c "import sys,json; data=json.load(sys.stdin); [print(f'{t[\"labels\"][\"job\"]}: {t[\"labels\"][\"instance\"]} UP={t[\"health\"]}') for t in data['data']['activeTargets']]"

# Выполнить произвольный PromQL запрос
curl -s 'http://localhost:9091/api/v1/query?query=up{job="aws-node-exporter"}' \
  | python3 -m json.tool
```

---

## 13. Ссылки

- [Grafana Dashboards API](https://grafana.com/docs/grafana/latest/developers/http_api/dashboard/)
- [PromQL Cheat Sheet](https://promlabs.com/promql-cheat-sheet/)
- [Локальный стек мониторинга](../docker/monitoring/docker-compose.yml)
- [Prometheus config](../docker/monitoring/prometheus.yml)
- [Дашборд AWS K3s — System](../docker/monitoring/grafana-aws-dashboard.json)
- [Дашборд AWS EC2 — System](../docker/monitoring/grafana-aws-ec2.json)
- [Дашборд LLM API](../docker/monitoring/grafana-llm-dashboard.json)
- [aws-tunnel.sh](../scripts/aws-tunnel.sh)
- [Отчёт о диагностике](CheckAndRepare.md)