"""Client addresses and networks allowed to use the proxy."""

import ipaddress
from pathlib import Path

from squid_setup.common.listfile import read_list


def load_allowed_hosts(path: Path) -> list[str]:
    networks = []
    for entry in read_list(path):
        try:
            net = ipaddress.ip_network(entry, strict=False)
        except ValueError as err:
            raise ValueError(f"{path}: {err}") from None
        networks.append(net)
    return [str(n) for n in ipaddress.collapse_addresses(networks)]
