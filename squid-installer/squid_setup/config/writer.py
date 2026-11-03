"""Writes squid.conf with a backup, and asks squid to check it."""

import logging
import shutil
import subprocess
from datetime import datetime
from pathlib import Path

log = logging.getLogger(__name__)


def write_config(text: str, path: Path, keep_backup: bool = True) -> Path:
    backup = path.with_name(f"{path.name}.{datetime.now():%Y%m%d-%H%M%S}.bak")
    if keep_backup and path.exists():
        shutil.copy2(path, backup)
        log.info("previous config kept as %s", backup)
    path.write_text(text)
    path.chmod(0o644)
    return backup


def validate_config(path: Path) -> bool:
    result = subprocess.run(["squid", "-k", "parse", "-f", str(path)],
                            capture_output=True, text=True)
    if result.returncode != 0:
        log.error(result.stderr.strip())
    return result.returncode == 0
