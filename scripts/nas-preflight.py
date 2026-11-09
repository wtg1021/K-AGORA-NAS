"""Check the NAS port and writable persistent volume; back up SQLite before deploy."""
import os
import socket
import sqlite3
from datetime import datetime, timezone
from pathlib import Path

path = Path(os.environ['DATABASE_PATH'])
if not path.is_absolute() or path.parent != Path('/data'):
    raise SystemExit('DATABASE_PATH must be a file directly inside /data.')
probe = path.parent / '.k-agora-write-check'
try:
    probe.write_text('ok', encoding='utf-8')
    probe.unlink()
except OSError as exc:
    raise SystemExit('The persistent /data volume is not writable by UID 10001.') from exc
port = int(os.environ['PORT'])
if str(port) != os.environ.get('K_AGORA_EXISTING_PORT', ''):
    try:
        with socket.socket() as sock:
            sock.bind((os.environ.get('HOST', '0.0.0.0'), port))
    except OSError as exc:
        raise SystemExit(f'Port {port} is already in use; choose a free PORT before deployment.') from exc
if path.exists():
    backups = path.parent / 'backups'
    backups.mkdir(exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    backup = backups / ('predeploy-' + stamp + '.sqlite3')
    with sqlite3.connect(path.as_uri() + '?mode=ro', uri=True) as source:
        with sqlite3.connect(backup) as destination:
            source.backup(destination)
    print('Created a consistent pre-deployment SQLite backup in /data/backups.')
print(f'Preflight passed: data volume writable; port {port} checked.')
