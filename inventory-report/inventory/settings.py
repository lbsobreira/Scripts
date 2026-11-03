"""inventory.ini and hosts.yaml."""

import configparser
import logging
import os
from dataclasses import dataclass
from pathlib import Path

import yaml

log = logging.getLogger(__name__)


@dataclass
class Settings:
    output_dir: Path
    workers: int
    timeout: int
    ssh_user: str
    ssh_key: Path
    winrm_user: str
    winrm_transport: str
    snmp_community: str
    log_level: str
    log_file: str | None


def load_settings(path: Path) -> Settings:
    cp = configparser.ConfigParser()
    if not cp.read(path):
        raise SystemExit(f"cannot read {path}")
    general = cp["general"]
    return Settings(
        output_dir=Path(general.get("output_dir", "./out")).expanduser(),
        workers=general.getint("workers", 8),
        timeout=general.getint("timeout", 20),
        ssh_user=cp.get("ssh", "user", fallback="inventory"),
        ssh_key=Path(cp.get("ssh", "key", fallback="~/.ssh/id_ed25519")).expanduser(),
        winrm_user=cp.get("winrm", "user", fallback="LAB\\svc-inventory"),
        winrm_transport=cp.get("winrm", "transport", fallback="kerberos"),
        # The community is a secret: it comes from the environment, never the file.
        snmp_community=os.environ.get("INVENTORY_SNMP_COMMUNITY", "public"),
        log_level=general.get("log_level", "INFO").upper(),
        log_file=general.get("log_file") or None,
    )


def load_hosts(path: Path) -> list[dict]:
    with open(path, encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}
    hosts = []
    for group, entries in data.items():
        for entry in entries or []:
            if isinstance(entry, str):
                entry = {"name": entry}
            entry.setdefault("kind", group)
            hosts.append(entry)
    log.debug("%d hosts in %s", len(hosts), path)
    return hosts
