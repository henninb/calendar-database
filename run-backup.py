#!/usr/bin/env python3

import argparse
import logging
import os
import shutil
import subprocess
import sys
from datetime import date
from pathlib import Path

DB_NAME = "calendar_db"
DEFAULT_PORT = 5432
DEFAULT_VERSION = "v17-1"
USERNAME = "henninb"
REMOTE_DEST = "raspi:/home/pi/downloads/calendar-db-bkp/"

CSV_EXPORTS = [
    ("categories",   "SELECT id, name, color, icon, description, is_seeded FROM categories ORDER BY id"),
    ("credit_cards", "SELECT id, name, issuer, last_four, statement_close_day, grace_period_days, weekend_shift, cycle_days, cycle_reference_date, due_day_same_month, due_day_next_month, annual_fee_month, is_active, created_at, is_seeded FROM credit_cards ORDER BY id"),
    ("persons",      "SELECT id, name, email FROM persons ORDER BY id"),
    ("events",       "SELECT id, title, category_id, credit_card_id, rrule, dtstart, dtend_rule, duration_days, description, location, reminder_days, priority, amount, is_active, generates_tasks, gcal_calendar_id, created_at, updated_at, is_seeded FROM events ORDER BY id"),
    ("occurrences",  "SELECT id, event_id, occurrence_date, status, notes, gcal_event_id, synced_at, created_at FROM occurrences ORDER BY id"),
    ("tasks",        "SELECT id, occurrence_id, category_id, title, description, status, priority, assignee_id, due_date, estimated_minutes, recurrence, gtask_id, synced_at, parent_task_id, completed_at, created_at, updated_at FROM tasks ORDER BY id"),
    ("subtasks",     'SELECT id, task_id, title, status, due_date, "order", gtask_id, created_at, updated_at, completed_at FROM subtasks ORDER BY id'),
]


def setup_logging(log_file: Path) -> logging.Logger:
    logger = logging.getLogger("backup")
    logger.setLevel(logging.DEBUG)
    fmt = logging.Formatter("[%(asctime)s] %(levelname)s: %(message)s", datefmt="%Y-%m-%d %H:%M:%S")
    for handler in (logging.FileHandler(log_file), logging.StreamHandler()):
        handler.setFormatter(fmt)
        logger.addHandler(handler)
    return logger


def check_dependencies(logger: logging.Logger) -> None:
    missing = [cmd for cmd in ("psql", "pg_dump", "scp") if not shutil.which(cmd)]
    if missing:
        logger.error(f"Missing required tools: {', '.join(missing)}")
        sys.exit(2)
    logger.info("All required dependencies found")


def check_pgpass(server: str, port: int, logger: logging.Logger) -> None:
    pgpass = Path.home() / ".pgpass"
    if not pgpass.exists():
        logger.error(
            f"~/.pgpass not found. Create it:\n"
            f"  {server}:{port}:{DB_NAME}:{USERNAME}:your_password\n"
            f"  chmod 600 ~/.pgpass"
        )
        sys.exit(1)
    perms = oct(pgpass.stat().st_mode)[-3:]
    if perms != "600":
        logger.error(f"~/.pgpass has incorrect permissions ({perms}). Run: chmod 600 ~/.pgpass")
        sys.exit(1)
    os.environ["PGPASSFILE"] = str(pgpass)
    logger.info("~/.pgpass found with correct permissions")


def test_db_connection(server: str, port: int, logger: logging.Logger) -> None:
    logger.info(f"Testing connectivity to {server}:{port}")
    result = subprocess.run(
        ["psql", "-h", server, "-p", str(port), "-U", USERNAME, "-d", DB_NAME, "-c", "SELECT 1;"],
        capture_output=True,
    )
    if result.returncode != 0:
        logger.error(f"Cannot connect to {server}:{port} as {USERNAME}")
        logger.error("Check: server running, network reachable, ~/.pgpass credentials correct")
        sys.exit(3)
    logger.info("Database connectivity test passed")


def generate_unique_path(base: str, ext: str) -> Path:
    path = Path(f"{base}.{ext}")
    counter = 0
    while path.exists():
        counter += 1
        if counter > 99:
            raise RuntimeError("100+ backup files exist — clean up old backups before running again")
        path = Path(f"{base}-{counter}.{ext}")
    return path


def run_pg_dump(server: str, port: int, out_path: Path, logger: logging.Logger) -> None:
    logger.info(f"Creating pg_dump: {out_path}")
    with open(out_path, "wb") as f:
        result = subprocess.run(
            ["pg_dump", "-h", server, "-p", str(port), "-U", USERNAME, "-F", "t", "-d", DB_NAME],
            stdout=f,
            stderr=subprocess.PIPE,
        )
    if result.returncode != 0:
        raise RuntimeError(f"pg_dump failed: {result.stderr.decode().strip()}")
    size = out_path.stat().st_size
    if size == 0:
        raise RuntimeError("pg_dump produced an empty file")
    logger.info(f"pg_dump complete: {size / 1024:.1f} KB")


def export_csv(server: str, port: int, table: str, query: str, logger: logging.Logger) -> Path:
    csv_path = Path(f"{table}.csv")
    copy_cmd = f"\\copy ({query}) TO '{csv_path}' CSV HEADER"
    result = subprocess.run(
        ["psql", "-h", server, "-p", str(port), "-U", USERNAME, "-d", DB_NAME, "-c", copy_cmd],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(f"CSV export of {table} failed: {result.stderr.strip()}")
    if not csv_path.exists() or csv_path.stat().st_size == 0:
        raise RuntimeError(f"CSV export of {table} produced an empty or missing file")
    logger.info(f"  {table}: {csv_path.stat().st_size} bytes")
    return csv_path


def copy_to_remote(local_path: Path, logger: logging.Logger) -> None:
    logger.info(f"Copying {local_path} to {REMOTE_DEST}")
    result = subprocess.run(
        ["scp", "-p", str(local_path), REMOTE_DEST],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(f"scp failed: {result.stderr.strip()}")
    logger.info("Remote copy successful")


def main() -> None:
    today = date.today().strftime("%Y-%m-%d")
    log_file = Path(f"calendar-db-backup-{today}.log")
    logger = setup_logging(log_file)

    parser = argparse.ArgumentParser(description=f"Backup {DB_NAME} PostgreSQL database")
    parser.add_argument("server", help="Database server hostname or IP")
    parser.add_argument("port", nargs="?", type=int, default=DEFAULT_PORT,
                        help=f"Database port (default: {DEFAULT_PORT})")
    parser.add_argument("version", nargs="?", default=DEFAULT_VERSION,
                        help=f"Version tag for the backup filename (default: {DEFAULT_VERSION})")
    args = parser.parse_args()

    logger.info(f"server={args.server} port={args.port} version={args.version} user={USERNAME}")

    check_dependencies(logger)
    check_pgpass(args.server, args.port, logger)
    test_db_connection(args.server, args.port, logger)

    backup_path = generate_unique_path(f"calendar_db-{args.version}-{today}", "tar")
    logger.info(f"Backup file: {backup_path}")

    csv_files: list[Path] = []

    try:
        run_pg_dump(args.server, args.port, backup_path, logger)

        logger.info("Exporting CSV tables")
        for table, query in CSV_EXPORTS:
            csv_files.append(export_csv(args.server, args.port, table, query, logger))

        copy_to_remote(backup_path, logger)

    except Exception as exc:
        logger.error(f"Backup failed: {exc}")
        if backup_path.exists():
            backup_path.unlink()
            logger.info(f"Removed partial backup: {backup_path}")
        sys.exit(4)

    finally:
        for f in csv_files:
            if f.exists():
                f.unlink()
                logger.info(f"Cleaned up {f.name}")

    logger.info(f"SUCCESS: {backup_path} ({backup_path.stat().st_size / 1024:.1f} KB)")


if __name__ == "__main__":
    main()
