#!/usr/bin/env python3
"""labctl - small command line client for the lab's management API.

    labctl vm list
    labctl vm start web-01
    labctl vm stop web-01 --force
    labctl dns add app01 10.32.0.40
    labctl dns remove app01
    labctl backup run --target nas-01 --keep 7

Settings come from ~/.config/labctl/config.toml; LABCTL_HOST and LABCTL_TOKEN
override the file.
"""

import argparse
import logging
import sys

from labctl_core import load_config, LabClient
from labctl_core.commands import vm, dns, backup
from labctl_core.errors import LabctlError

log = logging.getLogger("labctl")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="labctl", description=__doc__.splitlines()[0])
    parser.add_argument("-c", "--config", help="path to config.toml")
    parser.add_argument("-v", "--verbose", action="store_true")
    sub = parser.add_subparsers(dest="area", required=True)

    # vm
    p_vm = sub.add_parser("vm", help="virtual machines")
    vm_sub = p_vm.add_subparsers(dest="action", required=True)
    p = vm_sub.add_parser("list", help="list VMs and their state")
    p.add_argument("--host", help="only the VMs on this hypervisor")
    p.set_defaults(func=vm.run_list)
    p = vm_sub.add_parser("start")
    p.add_argument("name")
    p.set_defaults(func=vm.run_start)
    p = vm_sub.add_parser("stop")
    p.add_argument("name")
    p.add_argument("--force", action="store_true", help="turn off instead of shutting down")
    p.set_defaults(func=vm.run_stop)

    # dns
    p_dns = sub.add_parser("dns", help="DNS records in the lab zone")
    dns_sub = p_dns.add_subparsers(dest="action", required=True)
    p = dns_sub.add_parser("add")
    p.add_argument("name")
    p.add_argument("address")
    p.add_argument("--ttl", type=int, default=3600)
    p.set_defaults(func=dns.run_add)
    p = dns_sub.add_parser("remove")
    p.add_argument("name")
    p.set_defaults(func=dns.run_remove)

    # backup
    p_backup = sub.add_parser("backup", help="backup jobs")
    backup_sub = p_backup.add_subparsers(dest="action", required=True)
    p = backup_sub.add_parser("run")
    p.add_argument("--target", default=None, help="backup target (default: from config)")
    p.add_argument("--keep", type=int, default=None, help="restore points to keep")
    p.set_defaults(func=backup.run_backup)

    return parser


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.WARNING,
        format="%(levelname)s %(name)s: %(message)s",
    )

    try:
        cfg = load_config(args.config)
        args.client = LabClient(cfg.host, cfg.token, verify=cfg.verify_tls)
        args.cfg = cfg
        return args.func(args) or 0
    except LabctlError as err:
        log.error("%s", err)
        return err.exit_code
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    sys.exit(main())
