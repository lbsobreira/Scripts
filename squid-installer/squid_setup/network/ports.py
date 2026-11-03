"""Destination ports the proxy lets through."""

from pathlib import Path

from squid_setup.common.listfile import read_list

DEFAULT_PORTS = [80, 443]


def load_ports(path: Path) -> list[int]:
    if not path.exists():
        return list(DEFAULT_PORTS)
    ports = set()
    for entry in read_list(path):
        if "-" in entry:
            start, end = (int(p) for p in entry.split("-", 1))
            ports.update(range(start, end + 1))
        else:
            ports.add(int(entry))
    bad = [p for p in ports if not 1 <= p <= 65535]
    if bad:
        raise ValueError(f"{path}: ports out of range: {bad}")
    return sorted(ports)


def format_port_acl(name: str, ports: list[int]) -> list[str]:
    return [f"acl {name} port {port}" for port in ports]
