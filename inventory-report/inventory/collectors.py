"""SSH, WinRM and SNMP collectors."""

import json
import logging
import subprocess

import paramiko

from .base import Collector, CollectorError
from .models import Disk

log = logging.getLogger(__name__)

LINUX_FACTS = r"""
. /etc/os-release
echo "os=$NAME"
echo "version=$VERSION_ID"
echo "cpu_count=$(nproc)"
echo "memory_bytes=$(awk '/MemTotal/ {print $2 * 1024}' /proc/meminfo)"
echo "uptime_s=$(cut -d. -f1 /proc/uptime)"
df -P -B1 -x tmpfs -x devtmpfs | awk 'NR>1 {print "disk=" $6 ":" $2 ":" $4}'
"""

WINDOWS_FACTS = (
    "$os = Get-CimInstance Win32_OperatingSystem; "
    "$cs = Get-CimInstance Win32_ComputerSystem; "
    "[pscustomobject]@{os=$os.Caption; version=$os.Version; cpu_count=$cs.NumberOfLogicalProcessors; "
    "memory_bytes=$cs.TotalPhysicalMemory; uptime_s=((Get-Date)-$os.LastBootUpTime).TotalSeconds; "
    "disks=@(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | "
    "ForEach-Object { @{mount=$_.DeviceID; size=$_.Size; free=$_.FreeSpace} })} | ConvertTo-Json -Depth 3"
)


class SshCollector(Collector):
    kind = "linux"

    def collect(self, entry: dict) -> dict:
        client = paramiko.SSHClient()
        client.load_system_host_keys()
        client.set_missing_host_key_policy(paramiko.RejectPolicy())
        try:
            client.connect(entry["name"], username=entry.get("user", self.settings.ssh_user),
                           key_filename=str(self.settings.ssh_key), timeout=self.timeout)
            _, stdout, stderr = client.exec_command(LINUX_FACTS, timeout=self.timeout)
            text = stdout.read().decode()
            if stdout.channel.recv_exit_status() != 0:
                raise CollectorError(stderr.read().decode().strip() or "facts script failed")
        except (paramiko.SSHException, OSError) as err:
            raise CollectorError(f"ssh: {err}") from None
        finally:
            client.close()
        return parse_key_values(text)


class WinRmCollector(Collector):
    kind = "windows"

    def collect(self, entry: dict) -> dict:
        # pywinrm needs a password; with Kerberos the ticket of the account running the
        # report is used instead, so this goes through pwsh and its own remoting.
        cmd = ["pwsh", "-NoProfile", "-Command",
               f"Invoke-Command -ComputerName {entry['name']} -ScriptBlock {{ {WINDOWS_FACTS} }}"]
        try:
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=self.timeout * 3)
        except subprocess.TimeoutExpired:
            raise CollectorError("WinRM timed out") from None
        if proc.returncode != 0:
            raise CollectorError(proc.stderr.strip().splitlines()[-1] if proc.stderr else "pwsh failed")
        raw = json.loads(proc.stdout)
        raw["disks"] = [Disk(d["mount"], round(d["size"] / 2**30, 1), round(d["free"] / 2**30, 1))
                        for d in raw.get("disks") or []]
        return raw


class SnmpCollector(Collector):
    kind = "snmp"

    OIDS = {
        "os": "1.3.6.1.2.1.1.1.0",        # sysDescr
        "uptime_s": "1.3.6.1.2.1.1.3.0",  # sysUpTime, in hundredths
    }

    def collect(self, entry: dict) -> dict:
        raw = {}
        for key, oid in self.OIDS.items():
            raw[key] = self._snmpget(entry["name"], oid)
        if raw.get("uptime_s"):
            raw["uptime_s"] = int(raw["uptime_s"]) // 100
        return raw

    def run(self, entry: dict):
        host = super().run(entry)
        host.os = host.os.split(",")[0][:60]
        return host

    def _snmpget(self, host: str, oid: str) -> str:
        proc = subprocess.run(
            ["snmpget", "-v2c", "-c", self.settings.snmp_community, "-Oqv", "-t", str(self.timeout), host, oid],
            capture_output=True, text=True,
        )
        if proc.returncode != 0:
            raise CollectorError(f"snmpget {oid}: {proc.stderr.strip()}")
        return proc.stdout.strip().strip('"')


def parse_key_values(text: str) -> dict:
    raw = {"disks": []}
    for line in text.splitlines():
        key, _, value = line.partition("=")
        if key == "disk":
            mount, size, free = value.rsplit(":", 2)
            raw["disks"].append(Disk(mount, round(int(size) / 2**30, 1), round(int(free) / 2**30, 1)))
        elif key:
            raw[key] = value
    return raw


COLLECTORS = {
    "linux": SshCollector,
    "windows": WinRmCollector,
    "snmp": SnmpCollector,
}


def make_collector(kind: str, settings) -> Collector:
    try:
        cls = COLLECTORS[kind]
    except KeyError:
        raise CollectorError(f"unknown host kind {kind!r}") from None
    return cls(settings)
