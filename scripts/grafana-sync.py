#!/usr/bin/env python3
"""
grafana-sync.py — автоматичний імпорт/експорт дашбордів Grafana
==================================================================

Призначення:
    Імпортувати JSON-файли дашбордів з docker/monitoring/ у Grafana
    або експортувати наявні дашборди з Grafana назад у файли.

Використання:
    python3 scripts/grafana-sync.py import            # імпорт усіх дашбордів
    python3 scripts/grafana-sync.py import --file grafana-aws-ec2.json  # один файл
    python3 scripts/grafana-sync.py export            # експорт усіх дашбордів
    python3 scripts/grafana-sync.py export --uid aws-ec2-system  # один дашборд
    python3 scripts/grafana-sync.py list              # список дашбордів у Grafana

Змінні оточення (або значення за замовчуванням):
    GRAFANA_URL      — http://localhost:3000
    GRAFANA_USER     — admin
    GRAFANA_PASSWORD — devops123
    DASHBOARDS_DIR   — docker/monitoring/

Залежності: requests (pip3 install requests)
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
    print("❌  Потрібно встановити requests:  pip3 install requests")
    sys.exit(1)

# ─── Конфігурація ────────────────────────────────────────────────────────────

GRAFANA_URL = os.getenv("GRAFANA_URL", "http://localhost:3000")
GRAFANA_USER = os.getenv("GRAFANA_USER", "admin")
GRAFANA_PASSWORD = os.getenv("GRAFANA_PASSWORD", "devops123")

# Шлях до директорії з JSON-файлами дашбордів (відносно кореня проекту)
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
DASHBOARDS_DIR = os.getenv("DASHBOARDS_DIR", str(PROJECT_ROOT / "docker" / "monitoring"))

AUTH = (GRAFANA_USER, GRAFANA_PASSWORD)
HEADERS = {"Content-Type": "application/json"}


# ─── Допоміжні функції ─────────────────────────────────────────────────────

def grafana_api(method, path, data=None):
    """Універсальний виклик Grafana HTTP API."""
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
        print(f"❌  Не можу підключитися до Grafana за адресою {GRAFANA_URL}")
        print(f"    Перевірте, чи запущено контейнер Grafana та чи правильний URL.")
        sys.exit(1)
    except requests.exceptions.HTTPError as e:
        print(f"❌  HTTP {e.response.status_code}: {e.response.text}")
        sys.exit(1)


def find_dashboard_files(directory=None, pattern="grafana-*.json"):
    """Знайти всі JSON-файли дашбордів у директорії."""
    if directory is None:
        directory = DASHBOARDS_DIR
    path_pattern = os.path.join(directory, pattern)
    files = sorted(glob.glob(path_pattern))
    return files


def validate_dashboard_json(filepath):
    """Перевірити, що JSON-файл — коректний дашборд Grafana."""
    try:
        with open(filepath, "r", encoding="utf-8") as f:
            data = json.load(f)
        if "title" not in data:
            print(f"⚠️   {filepath.name}: немає поля 'title' — пропускаю")
            return None
        return data
    except json.JSONDecodeError as e:
        print(f"⚠️   {filepath.name}: помилка JSON ({e}) — пропускаю")
        return None


# ─── Команди ─────────────────────────────────────────────────────────────────

def cmd_import(args):
    """Імпортувати дашборди з файлів у Grafana."""
    if args.file:
        files = [Path(args.file)]
        if not files[0].is_absolute():
            files[0] = Path(DASHBOARDS_DIR) / files[0]
    else:
        files = find_dashboard_files()
        if not files:
            print(f"⚠️   Файли дашбордів не знайдено в {DASHBOARDS_DIR}")
            return

    imported = 0
    for filepath in files:
        filepath = Path(filepath)
        dashboard = validate_dashboard_json(filepath)
        if dashboard is None:
            continue

        title = dashboard.get("title", filepath.stem)
        uid = dashboard.get("uid", "")

        print(f"📤  Імпортую: {title} ({filepath.name})", end=" ... ", flush=True)

        payload = {
            "dashboard": dashboard,
            "overwrite": True,
            "message": f"Imported by grafana-sync.py from {filepath.name}",
        }

        grafana_api("POST", "/dashboards/db", data=payload)
        print("✅")
        imported += 1

    print(f"\n✅  Імпортовано дашбордів: {imported}")


def cmd_export(args):
    """Експортувати дашборди з Grafana у файли."""
    if args.uid:
        uids = [args.uid]
    else:
        # Отримати список усіх дашбордів
        search_result = grafana_api("GET", "/search?type=dash-db")
        uids = [item["uid"] for item in search_result]

    if not uids:
        print("⚠️   У Grafana не знайдено жодного дашборда")
        return

    exported = 0
    for uid in uids:
        print(f"📥  Експортую UID: {uid}", end=" ... ", flush=True)

        dashboard_data = grafana_api("GET", f"/dashboards/uid/{uid}")

        # Витягуємо сам дашборд і прибираємо службові поля
        dashboard = dashboard_data.get("dashboard", {})

        # Зберігаємо
        title = dashboard.get("title", uid)
        # Створюємо ім'я файлу: grafana-{slug}.json
        slug = "".join(c if c.isalnum() or c in "-_" else "_" for c in title.lower().replace(" ", "-"))
        filename = f"grafana-{slug}.json"
        filepath = Path(DASHBOARDS_DIR) / filename

        with open(filepath, "w", encoding="utf-8") as f:
            json.dump(dashboard, f, indent=2, ensure_ascii=False)

        print(f"✅  → {filepath.name}")
        exported += 1

    print(f"\n✅  Експортовано дашбордів: {exported}")


def cmd_list(args):
    """Показати список дашбордів у Grafana."""
    search_result = grafana_api("GET", "/search?type=dash-db")

    if not search_result:
        print("📭  У Grafana немає дашбордів")
        return

    print(f"{'UID':<30} {'Title':<40} {'Tags':<30}")
    print("-" * 100)
    for item in search_result:
        uid = item.get("uid", "")
        title = item.get("title", "")
        tags = ", ".join(item.get("tags", []))
        print(f"{uid:<30} {title:<40} {tags:<30}")

    print(f"\n📊  Всього: {len(search_result)} дашбордів")


def cmd_health(args):
    """Перевірити доступність Grafana API."""
    try:
        resp = requests.get(f"{GRAFANA_URL}/api/health", timeout=5)
        resp.raise_for_status()
        data = resp.json()
        print(f"✅  Grafana доступна: {GRAFANA_URL}")
        print(f"   Version: {data.get('version', 'unknown')}")
        print(f"   Database: {data.get('database', 'unknown')}")
    except requests.exceptions.ConnectionError:
        print(f"❌  Не можу підключитися до Grafana {GRAFANA_URL}")
        print(f"    Перевірте, чи запущено контейнер Grafana")
        sys.exit(1)
    except requests.exceptions.HTTPError as e:
        print(f"❌  HTTP {e.response.status_code}: {e.response.text}")
        sys.exit(1)


# ─── CLI ─────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="grafana-sync — автоматичний імпорт/експорт дашбордів Grafana",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    subparsers = parser.add_subparsers(dest="command", help="Команда")

    # import
    p_import = subparsers.add_parser("import", help="Імпортувати дашборди в Grafana")
    p_import.add_argument("--file", "-f", help="Імпортувати тільки один файл (grafana-*.json)")

    # export
    p_export = subparsers.add_parser("export", help="Експортувати дашборди з Grafana у файли")
    p_export.add_argument("--uid", "-u", help="Експортувати тільки один дашборд за UID")

    # list
    subparsers.add_parser("list", help="Показати список дашбордів у Grafana")

    # health
    subparsers.add_parser("health", help="Перевірити доступність Grafana API")

    args = parser.parse_args()

    if args.command is None:
        parser.print_help()
        sys.exit(1)

    # Маршрутизація команд
    commands = {
        "import": cmd_import,
        "export": cmd_export,
        "list": cmd_list,
        "health": cmd_health,
    }

    commands[args.command](args)


if __name__ == "__main__":
    main()