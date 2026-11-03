"""labctl dns add|remove"""

import ipaddress

from ..errors import LabctlError, NotFound
from ..output import ok, warn


def _fqdn(name: str, zone: str) -> str:
    return name if name.endswith("." + zone) else f"{name}.{zone}"


def run_add(args):
    try:
        ipaddress.ip_address(args.address)
    except ValueError:
        raise LabctlError(f"not an IP address: {args.address}") from None
    fqdn = _fqdn(args.name, args.cfg.dns_zone)
    args.client.post("/dns/records", {"name": fqdn, "type": "A", "value": args.address, "ttl": args.ttl})
    ok(f"{fqdn} -> {args.address}")


def run_remove(args):
    fqdn = _fqdn(args.name, args.cfg.dns_zone)
    try:
        args.client.delete(f"/dns/records/{fqdn}")
    except NotFound:
        warn(f"{fqdn} does not exist")
        return 0
    ok(f"{fqdn} removed")
