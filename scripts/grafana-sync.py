#!/usr/bin/env python3
"""
grafana-sync.py — автоматический импорт/экспорт дашбордов Grafana
=================================================================

Назначение:
    Импортировать JSON-файлы дашбордов из docker/monitoring/ в Grafana
    или экспортировать существующие дашборды из Grafana обратно в файлы.

Использование:
    python3 scripts/grafana-sync.py import            # импорт всех дашбордов
    python3 scripts/grafana-sync.py import --file grafana-aws-ec2.json  # один файл
    python3 scripts/grafana-sync.py export            # экспорт всех дашбордов
    python3 scripts/grafana-sync.py export --uid aws-ec2-system  # один дашборд
    python3 scripts/grafana-sync.py list              # список дашбордов в Grafana

Переменные окружения (или значения по умолчанию):
    GRAFANA_URL      — http://localhost:3000
    GRAFANA_USER     — admin
    GRAFANA_PASSWORD — devops123
    DASHBOARDS_DIR   — docker/monitoring/

Зависимости: requests (pip3 install requests)
"""

import argparse
import json
import os
import sys
import glob
from pathlib import Path

try:
    import requests
except ImportError:
    print("❌  Требуется установить requests:  pip3 install requests")
    sys.exit(1)

# ─── Конфигурация ───────────────────────────────────────────────────────────

GRAFANA_URL = os.getenv("GRAFANA_URL", "http://localhost:3000")
GRAFANA_USER = os.getenv("GRAFANA_USER", "admin")
GRAFANA_PASSWORD = os.getenv("GRAFANA_PASSWORD", "devops123")

# Путь к директории с JSON-файлами дашбордов (относительно корня проекта)
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
DASHBOARDS_DIR = os.getenv("DASHBOARDS_DIR", str(PROJECT_ROOT / "docker" / "monitoring"))

AUTH = (GRAFANA_USER, GRAFANA_PASSWORD)
HEADERS = {"Content-Type": "application/json"}


# ─── Вспомогательные функции ────────────────────────────────────────────────

def grafana_api(method, path, data=None):
    """Универсальный вызов Grafana HTTP API."""
    url = f"{GRAFANA_URL}/api{path}"
    try:
        if method == "GET":
            resp = requests.get(url, auth=AUTH, headers=HEADERS, timeout=10)
        elif method == "POST":
            resp = requests.post(url, auth=AUTH, headers=HEADERS, json=data, timeout=10)
        elif method == "DELETE":
            resp = requests.delete(url, auth=AUTH, headers=HEADERS, timeout=10)
        else:
            raise ValueError(f"Unsupported method: {method}")

        resp.raise_for_status()
        return resp.json()
    except requests.exceptions.ConnectionError:
        print(f"❌  Не могу connected к Grafana по адресу {GRAFANA_URL}")
        print(f"    Проверьте, запущен ли контейнер Grafana и правильный ли URL.")
        sys.exit(1)
    except requests.exceptions.HTTPError as e:
        print(f"❌  HTTP {e.response.status_code}: {e.response.text}")
        sys.exit(1)


def find_dashboard_files(directory=None, pattern="grafana-*.json"):
    """Найти все JSON-файлы дашбордов в директории."""
    if directory is None:
        directory = DASHBOARDS_DIR
    path_pattern = os.path.join(directory, pattern)
    files = sorted(glob.glob(path_pattern))
    return files


def validate_dashboard_json(filepath):
    """Проверить, что JSON-файл — корректный дашборд Grafana."""
    try:
        with open(filepath, "r", encoding="utf-8") as f:
            data = json.load(f)
        if "title" not in data:
            print(f"⚠️   {filepath.name}: нет поля 'title' — пропускаю")
            return None
        return data
    except json.JSONDecodeError as e:
        print(f"⚠️   {filepath.name}: ошибка JSON ({e}) — пропускаю")
        return None


# ─── Команды ────────────────────────────────────────────────────────────────

def cmd_import(args):
    """Импортировать дашборды из файлов в Grafana."""
    if args.file:
        files = [Path(args.file)]
        if not files[0].is_absolute():
            files[0] = Path(DASHBOARDS_DIR) / files[0]
    else:
        files = find_dashboard_files()
        if not files:
            print(f"⚠️   Файлы дашбордов не найдены в {DASHBOARDS_DIR}")
            return

    imported = 0
    for filepath in files:
        filepath = Path(filepath)
        dashboard = validate_dashboard_json(filepath)
        if dashboard is None:
            continue

        title = dashboard.get("title", filepath.stem)
        uid = dashboard.get("uid", "")

        print(f"📤  Импортирую: {title} ({filepath.name})", end=" ... ", flush=True)

        payload = {
            "dashboard": dashboard,
            "overwrite": True,
            "message": f"Imported by grafana-sync.py from {filepath.name}",
        }

        grafana_api("POST", "/dashboards/db", data=payload)
        print("✅")
        imported += 1

    print(f"\n✅  Импортировано дашбордов: {imported}")


def cmd_export(args):
    """Экспортировать дашборды из Grafana в файлы."""
    if args.uid:
        uids = [args.uid]
    else:
        # Получить список всех дашбордов
        search_result = grafana_api("GET", "/search?type=dash-db")
        uids = [item["uid"] for item in search_result]

    if not uids:
        print("⚠️   В Grafana не найдено ни одного дашборда")
        return

    exported = 0
    for uid in uids:
        print(f"📥  Экспортирую UID: {uid}", end=" ... ", flush=True)

        dashboard_data = grafana_api("GET", f"/dashboards/uid/{uid}")

        # Извлекаем сам дашборд и убираем служебные поля
        dashboard = dashboard_data.get("dashboard", {})

        # Сохраняем
        title = dashboard.get("title", uid)
        # Создаём имя файла: grafana-{slug}.json
        slug = "".join(c if c.isalnum() or c in "-_" else "_" for c in title.lower().replace(" ", "-"))
        filename = f"grafana-{slug}.json"
        filepath = Path(DASHBOARDS_DIR) / filename

        with open(filepath, "w", encoding="utf-8") as f:
            json.dump(dashboard, f, indent=2, ensure_ascii=False)

        print(f"✅  → {filepath.name}")
        exported += 1

    print(f"\n✅  Экспортировано дашбордов: {exported}")


def cmd_list(args):
    """Показать список дашбордов в Grafana."""
    search_result = grafana_api("GET", "/search?type=dash-db")

    if not search_result:
        print("📭  В Grafana нет дашбордов")
        return

    print(f"{'UID':<30} {'Title':<40} {'Tags':<30}")
    print("-" * 100)
    for item in search_result:
        uid = item.get("uid", "")
        title = item.get("title", "")
        tags = ", ".join(item.get("tags", []))
        print(f"{uid:<30} {title:<40} {tags:<30}")

    print(f"\n📊  Всего: {len(search_result)} дашбордов")


def cmd_health(args):
    """Проверить доступность Grafana API."""
    try:
        resp = requests.get(f"{GRAFANA_URL}/api/health", timeout=5)
        resp.raise_for_status()
        data = resp.json()
        print(f"✅  Grafana доступна: {GRAFANA_URL}")
        print(f"   Version: {data.get('version', 'unknown')}")
        print(f"   Database: {data.get('database', 'unknown')}")
    except requests.exceptions.ConnectionError:
        print(f"❌  Не могу connected к Grafana {GRAFANA_URL}")
        print(f"    Проверьте, запущен ли контейнер Grafana")
        sys.exit(1)
    except requests.exceptions.HTTPError as e:
        print(f"❌  HTTP {e.response.status_code}: {e.response.text}")
        sys.exit(1)


# ─── CLI ─────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="grafana-sync — автоматический импорт/экспорт дашбордов Grafana",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    subparsers = parser.add_subparsers(dest="command", help="Команда")

    # import
    p_import = subparsers.add_parser("import", help="Импортировать дашборды в Grafana")
    p_import.add_argument("--file", "-f", help="Импортировать только один файл (grafana-*.json)")

    # export
    p_export = subparsers.add_parser("export", help="Экспортировать дашборды из Grafana в файлы")
    p_export.add_argument("--uid", "-u", help="Экспортировать только один дашборд по UID")

    # list
    subparsers.add_parser("list", help="Показать список дашбордов в Grafana")

    # health
    subparsers.add_parser("health", help="Проверить доступность Grafana API")

    args = parser.parse_args()

    if args.command is None:
        parser.print_help()
        sys.exit(1)

    # Маршрутизация команд
    commands = {
        "import": cmd_import,
        "export": cmd_export,
        "list": cmd_list,
        "health": cmd_health,
    }

    commands[args.command](args)


if __name__ == "__main__":
    main()