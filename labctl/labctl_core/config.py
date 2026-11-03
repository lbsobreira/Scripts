"""Reads labctl's settings: the config file first, then the environment."""

import logging
import os
import tomllib
from dataclasses import dataclass
from pathlib import Path

from .errors import ConfigError

log = logging.getLogger(__name__)

DEFAULT_PATH = Path.home() / ".config" / "labctl" / "config.toml"
DEFAULT_HOST = "https://labapi.homelab.local"


@dataclass
class Config:
    host: str = DEFAULT_HOST
    token: str = ""
    verify_tls: bool = True
    backup_target: str = "nas-01"
    backup_keep: int = 14
    dns_zone: str = "homelab.local"


def load_config(path=None) -> Config:
    path = Path(path) if path else DEFAULT_PATH
    data = {}
    if path.exists():
        try:
            with path.open("rb") as fh:
                data = tomllib.load(fh)
        except tomllib.TOMLDecodeError as err:
            raise ConfigError(f"{path}: {err}") from None
        log.debug("read %s", path)
    else:
        log.debug("%s not found, using defaults", path)

    api = data.get("api", {})
    backup = data.get("backup", {})
    cfg = Config(
        host=api.get("host", DEFAULT_HOST),
        token=api.get("token", ""),
        verify_tls=api.get("verify_tls", True),
        backup_target=backup.get("target", "nas-01"),
        backup_keep=int(backup.get("keep", 14)),
        dns_zone=data.get("dns", {}).get("zone", "homelab.local"),
    )

    # The environment wins over the file.
    cfg.host = os.environ.get("LABCTL_HOST", cfg.host)
    cfg.token = os.environ.get("LABCTL_TOKEN", cfg.token)

    if not cfg.token:
        raise ConfigError("no API token: set api.token in the config or LABCTL_TOKEN")
    return cfg


def write_example(path: Path = DEFAULT_PATH) -> None:
    """Writes a starter config file. Was used by the old `labctl init`."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        '[api]\nhost = "https://labapi.homelab.local"\ntoken = ""\n\n'
        '[backup]\ntarget = "nas-01"\nkeep = 14\n'
    )
