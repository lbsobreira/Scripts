#!/usr/bin/env python3
"""Hardware and OS inventory of the lab, as an HTML and a CSV report.

Reads the host list from hosts.yaml and the collection settings from
inventory.ini, asks every host for its facts (SSH for Linux, WinRM for
Windows, SNMP for switches and the UPS) and writes the reports to the
output folder named in inventory.ini.

    ./report.py
    ./report.py --only linux --ini /etc/inventory/inventory.ini
"""

import argparse
import logging
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from inventory.settings import load_settings, load_hosts
from inventory.collectors import make_collector, CollectorError
from inventory.render import HtmlRenderer, CsvRenderer
from inventory.models import Host

HERE = Path(__file__).resolve().parent
log = logging.getLogger("inventory")


def collect_all(hosts, settings, workers: int) -> list[Host]:
    results = []
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {}
        for entry in hosts:
            collector = make_collector(entry["kind"], settings)
            futures[pool.submit(collector.run, entry)] = entry["name"]
        for fut in as_completed(futures):
            name = futures[fut]
            try:
                results.append(fut.result())
            except CollectorError as err:
                log.warning("%s: %s", name, err)
                results.append(Host.unreachable(name, str(err)))
    return sorted(results, key=lambda h: h.name)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="lab inventory report")
    ap.add_argument("--ini", type=Path, default=HERE / "inventory.ini")
    ap.add_argument("--hosts", type=Path, default=HERE / "hosts.yaml")
    ap.add_argument("--only", choices=["linux", "windows", "snmp"])
    args = ap.parse_args(argv)

    settings = load_settings(args.ini)
    logging.basicConfig(level=settings.log_level, format="%(asctime)s %(levelname)-7s %(message)s",
                        filename=settings.log_file)

    hosts = load_hosts(args.hosts)
    if args.only:
        hosts = [h for h in hosts if h["kind"] == args.only]
    log.info("collecting from %d hosts", len(hosts))

    inventory = collect_all(hosts, settings, settings.workers)

    out = settings.output_dir
    out.mkdir(parents=True, exist_ok=True)
    for renderer in (HtmlRenderer(HERE / "templates"), CsvRenderer()):
        path = renderer.write(inventory, out)
        log.info("wrote %s", path)

    failed = [h for h in inventory if not h.reachable]
    if failed:
        log.warning("%d hosts unreachable: %s", len(failed), ", ".join(h.name for h in failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
