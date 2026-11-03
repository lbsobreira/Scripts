#!/usr/bin/env python3
"""Install and configure Squid as a filtering forward proxy.

Reads the allowed client networks, destination domains and ports from the
lists in ./lists, writes /etc/squid/squid.conf, checks it with `squid -k parse`
and restarts the service.

    sudo ./install_squid.py --lists ./lists
    sudo ./install_squid.py --dry-run      # print the config, change nothing
"""

import argparse
import logging
import sys
from pathlib import Path

from squid_setup.system import packages, service
from squid_setup.config.builder import build_config
from squid_setup.config.writer import write_config, validate_config

log = logging.getLogger("install_squid")

DEFAULT_LISTS = Path(__file__).resolve().parent / "lists"


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--lists", type=Path, default=DEFAULT_LISTS,
                        help="folder with allowed_hosts.txt, dstdomains.txt, ports.txt")
    parser.add_argument("--port", type=int, default=3128, help="port Squid listens on")
    parser.add_argument("--config", type=Path, default=Path("/etc/squid/squid.conf"))
    parser.add_argument("--dry-run", action="store_true", help="print the config and stop")
    parser.add_argument("-v", "--verbose", action="store_true")
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO,
                        format="%(asctime)s %(levelname)s %(message)s")

    config_text = build_config(args.lists, listen_port=args.port)

    if args.dry_run:
        print(config_text)
        return 0

    if not packages.is_installed("squid"):
        packages.install("squid")

    backup = write_config(config_text, args.config)
    if not validate_config(args.config):
        log.error("squid rejected the new config; restoring %s", backup)
        write_config(backup.read_text(), args.config, keep_backup=False)
        return 1

    service.enable("squid")
    service.restart("squid")
    log.info("squid is running on port %d", args.port)
    return 0


if __name__ == "__main__":
    sys.exit(main())
