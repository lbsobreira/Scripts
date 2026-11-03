#!/usr/bin/env python3
"""Says whether this Linux host needs a reboot after patching.

Exit 100 when a reboot is needed, 0 when not. Run by scripts/linux/patch.sh
on the host itself.
"""

import os
import subprocess
import sys
from pathlib import Path

REBOOT_FLAG = Path("/var/run/reboot-required")


def running_kernel() -> str:
    return os.uname().release


def newest_installed_kernel() -> str | None:
    boot = sorted(Path("/boot").glob("vmlinuz-*"), key=lambda p: p.stat().st_mtime)
    return boot[-1].name.removeprefix("vmlinuz-") if boot else None


def needs_restarting() -> bool:
    """RHEL-likes: dnf's needs-restarting -r exits 1 when a reboot is needed."""
    try:
        return subprocess.run(["needs-restarting", "-r"], capture_output=True).returncode == 1
    except FileNotFoundError:
        return False


def main() -> int:
    if REBOOT_FLAG.exists():
        print("reboot required (flag file)")
        return 100
    newest = newest_installed_kernel()
    if newest and newest != running_kernel():
        print(f"reboot required (running {running_kernel()}, installed {newest})")
        return 100
    if needs_restarting():
        print("reboot required (needs-restarting)")
        return 100
    print("no reboot needed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
