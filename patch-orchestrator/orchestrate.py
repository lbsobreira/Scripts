#!/usr/bin/env python3
"""Patch the lab in waves.

waves.csv lists every host with its wave number and OS. Wave by wave, this:
  1. drains the host if it is behind the load balancer,
  2. patches it (Linux: scripts/linux/patch.sh over ssh; Windows:
     scripts/windows/Install-Patches.ps1 through pwsh remoting),
  3. reboots it when the patch run says so and waits for it to come back,
  4. puts it back in the pool,
and posts a summary to the webhook in PATCH_WEBHOOK.

A wave stops at the first failure; later waves are not started.

    ./orchestrate.py --wave 1
    ./orchestrate.py --all --dry-run
"""

import argparse
import csv
import logging
import os
import shlex
import sys
import time
from pathlib import Path

from helpers import run, wait_for_ssh, wait_for_port, notify, RunError

HERE = Path(__file__).resolve().parent
SCRIPTS = HERE / "scripts"
WAVES_FILE = HERE / "waves.csv"
LOG_DIR = Path(os.environ.get("PATCH_LOG_DIR", "/var/log/patching"))
LB_HOST = os.environ.get("PATCH_LB_HOST", "lb-01")
SSH_USER = os.environ.get("PATCH_SSH_USER", "patch")

log = logging.getLogger("orchestrate")


def read_waves(path: Path) -> dict[int, list[dict]]:
    waves: dict[int, list[dict]] = {}
    with open(path, newline="", encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            if row.get("skip", "").strip().lower() in ("1", "yes", "true"):
                log.info("skipping %s (marked skip)", row["host"])
                continue
            waves.setdefault(int(row["wave"]), []).append(row)
    return dict(sorted(waves.items()))


def drain(host: str, dry_run: bool):
    # haproxy's admin socket on the load balancer
    cmd = f"echo 'disable server web/{host}' | sudo socat stdio /run/haproxy/admin.sock"
    run(["ssh", f"{SSH_USER}@{LB_HOST}", cmd], dry_run=dry_run)


def undrain(host: str, dry_run: bool):
    cmd = f"echo 'enable server web/{host}' | sudo socat stdio /run/haproxy/admin.sock"
    run(["ssh", f"{SSH_USER}@{LB_HOST}", cmd], dry_run=dry_run)


def patch_linux(host: str, dry_run: bool) -> bool:
    """Copies the patch scripts over and runs them. Returns True when a reboot is needed."""
    remote_dir = "/tmp/patching"
    run(["ssh", f"{SSH_USER}@{host}", f"mkdir -p {remote_dir}"], dry_run=dry_run)
    run(["scp", "-q", "-r", str(SCRIPTS / "linux"), str(HERE / "reboot_check.py"),
         f"{SSH_USER}@{host}:{remote_dir}/"], dry_run=dry_run)
    result = run(["ssh", f"{SSH_USER}@{host}",
                  f"sudo bash {remote_dir}/linux/patch.sh --yes"], dry_run=dry_run, check=False)
    return result.returncode == 100


def patch_linux_local(host: str, dry_run: bool) -> bool:
    """The same through the local runner, for hosts only reachable from here with a jump host."""
    result = run(["bash", str(SCRIPTS / "linux/patch.sh"), host], dry_run=dry_run, check=False)
    return result.returncode == 100


def patch_windows(host: str, dry_run: bool) -> bool:
    log_file = LOG_DIR / f"{host}-{time.strftime('%Y%m%d')}.log"
    result = run(["pwsh", "-NoProfile", "-File", str(SCRIPTS / "windows/Install-Patches.ps1"),
                  "-ComputerName", host, "-LogPath", str(log_file)], dry_run=dry_run, check=False)
    if result.returncode not in (0, 3010):
        raise RunError(f"{host}: Install-Patches.ps1 exited {result.returncode}")
    return result.returncode == 3010


def reboot(row: dict, dry_run: bool):
    host = row["host"]
    if row["os"] == "windows":
        run(["pwsh", "-NoProfile", "-Command", f"Restart-Computer -ComputerName {host} -Force -Wait -For WinRM -Timeout 900"],
            dry_run=dry_run)
        return
    run(["ssh", f"{SSH_USER}@{host}", "sudo systemctl reboot"], dry_run=dry_run, check=False)
    time.sleep(20)
    if not dry_run:
        wait_for_ssh(host, timeout=900)


def patch_host(row: dict, dry_run: bool) -> str:
    host = row["host"]
    behind_lb = row.get("lb", "").lower() == "yes"
    if behind_lb:
        drain(host, dry_run)
    try:
        if row["os"] == "linux":
            needs_reboot = patch_linux_local(host, dry_run) if row.get("jump") else patch_linux(host, dry_run)
        elif row["os"] == "windows":
            needs_reboot = patch_windows(host, dry_run)
        else:
            raise RunError(f"{host}: unknown os {row['os']!r}")
        if needs_reboot:
            reboot(row, dry_run)
        if row.get("check_port") and not dry_run:
            wait_for_port(host, int(row["check_port"]), timeout=300)
    finally:
        if behind_lb:
            undrain(host, dry_run)
    return "rebooted" if needs_reboot else "patched"


def snapshot_hypervisor_vms(wave: list[dict], dry_run: bool):
    """Proxmox snapshot of every VM in the wave before it is patched."""
    for row in wave:
        if not row.get("vmid"):
            continue
        name = f"prepatch-{time.strftime('%Y%m%d')}"
        cmd = shlex.join(["qm", "snapshot", row["vmid"], name, "--description", f"before patching {row['host']}"])
        run(["ssh", f"root@{row['pve']}", cmd], dry_run=dry_run)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="patch the lab in waves")
    group = ap.add_mutually_exclusive_group(required=True)
    group.add_argument("--wave", type=int)
    group.add_argument("--all", action="store_true")
    ap.add_argument("--waves-file", type=Path, default=WAVES_FILE)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args(argv)

    LOG_DIR.mkdir(parents=True, exist_ok=True)
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
        handlers=[logging.StreamHandler(), logging.FileHandler(LOG_DIR / "orchestrate.log")],
    )

    waves = read_waves(args.waves_file)
    selected = waves if args.all else {args.wave: waves.get(args.wave, [])}
    summary = []
    for number, wave in selected.items():
        log.info("wave %d: %s", number, ", ".join(r["host"] for r in wave))
        snapshot_hypervisor_vms(wave, args.dry_run)
        for row in wave:
            try:
                summary.append(f"{row['host']}: {patch_host(row, args.dry_run)}")
            except RunError as err:
                log.error("%s", err)
                summary.append(f"{row['host']}: FAILED ({err})")
                notify(f"Patching stopped in wave {number}", summary)
                return 1

    # Keep the last 30 days of per-host logs.
    os.system(f"find {shlex.quote(str(LOG_DIR))} -name '*.log' -mtime +30 -delete")
    notify("Patching finished", summary)
    return 0


if __name__ == "__main__":
    sys.exit(main())
