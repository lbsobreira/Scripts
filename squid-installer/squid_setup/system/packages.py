"""Package installation on Debian/Ubuntu (apt) and RHEL-likes (dnf)."""

import logging
import shutil
import subprocess

log = logging.getLogger(__name__)


def _manager():
    for name in ("apt-get", "dnf", "yum"):
        if shutil.which(name):
            return name
    raise RuntimeError("no supported package manager found")


def is_installed(package: str) -> bool:
    if shutil.which("dpkg-query"):
        cmd = ["dpkg-query", "-W", "-f=${Status}", package]
    else:
        cmd = ["rpm", "-q", package]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.returncode == 0 and "not-installed" not in result.stdout


def install(package: str) -> None:
    manager = _manager()
    log.info("installing %s with %s", package, manager)
    if manager == "apt-get":
        subprocess.run([manager, "update"], check=True)
    subprocess.run([manager, "install", "-y", package], check=True)
