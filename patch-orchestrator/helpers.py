"""Small helpers shared by orchestrate.py and reboot_check.py."""

import json
import logging
import os
import socket
import subprocess
import time
import urllib.request

log = logging.getLogger("orchestrate")


class RunError(Exception):
    pass


def run(cmd: list[str], dry_run: bool = False, check: bool = True, timeout: int = 3600) -> subprocess.CompletedProcess:
    """Runs a command, logs it, and raises RunError when it fails and `check` is set."""
    log.info("$ %s", " ".join(cmd))
    if dry_run:
        return subprocess.CompletedProcess(cmd, 0, "", "")
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        raise RunError(f"timed out after {timeout}s: {cmd[0]}") from None
    for line in result.stdout.splitlines():
        log.debug("  %s", line)
    if check and result.returncode != 0:
        raise RunError(f"{cmd[0]} exited {result.returncode}: {result.stderr.strip()[:300]}")
    return result


def wait_for_port(host: str, port: int, timeout: int = 600) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            with socket.create_connection((host, port), timeout=5):
                return
        except OSError:
            time.sleep(10)
    raise RunError(f"{host}:{port} not answering after {timeout}s")


def wait_for_ssh(host: str, timeout: int = 600) -> None:
    wait_for_port(host, 22, timeout)


def notify(title: str, lines: list[str]) -> None:
    """Posts to the Slack-style webhook in PATCH_WEBHOOK; does nothing without it."""
    url = os.environ.get("PATCH_WEBHOOK")
    if not url:
        log.info("no PATCH_WEBHOOK set, not notifying")
        return
    body = json.dumps({"text": f"*{title}*\n" + "\n".join(lines)}).encode()
    req = urllib.request.Request(url, data=body, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            log.debug("webhook answered %s", resp.status)
    except OSError as err:
        log.warning("webhook failed: %s", err)


def human_duration(seconds: float) -> str:
    minutes, seconds = divmod(int(seconds), 60)
    hours, minutes = divmod(minutes, 60)
    return f"{hours}h{minutes:02d}m" if hours else f"{minutes}m{seconds:02d}s"
