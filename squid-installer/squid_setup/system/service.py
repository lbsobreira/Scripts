"""systemd service control."""

import subprocess


def _systemctl(*args):
    subprocess.run(["systemctl", *args], check=True)


def enable(name: str) -> None:
    _systemctl("enable", name)


def restart(name: str) -> None:
    _systemctl("restart", name)
