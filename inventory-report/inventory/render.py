"""HTML and CSV output."""

import csv
from datetime import datetime
from pathlib import Path

from jinja2 import Environment, FileSystemLoader, select_autoescape

DISK_WARN_PCT = 85


class Renderer:
    suffix = ""

    def filename(self, out: Path) -> Path:
        return out / f"inventory-{datetime.now():%Y%m%d}.{self.suffix}"

    def write(self, hosts, out: Path) -> Path:
        path = self.filename(out)
        self.render(hosts, path)
        return path

    def render(self, hosts, path: Path) -> None:
        raise NotImplementedError


class HtmlRenderer(Renderer):
    suffix = "html"

    def __init__(self, templates: Path):
        self.env = Environment(loader=FileSystemLoader(templates), autoescape=select_autoescape())

    def render(self, hosts, path: Path) -> None:
        template = self.env.get_template("report.html.j2")
        path.write_text(template.render(hosts=hosts, warn_pct=DISK_WARN_PCT,
                                        generated=datetime.now()), encoding="utf-8")


class CsvRenderer(Renderer):
    suffix = "csv"

    FIELDS = ["name", "kind", "os", "version", "cpu_count", "memory_gb", "uptime_days",
              "worst_disk", "worst_disk_pct", "reachable", "error"]

    def render(self, hosts, path: Path) -> None:
        with open(path, "w", newline="", encoding="utf-8") as fh:
            writer = csv.DictWriter(fh, fieldnames=self.FIELDS)
            writer.writeheader()
            for h in hosts:
                worst = h.worst_disk()
                writer.writerow({
                    "name": h.name, "kind": h.kind, "os": h.os, "version": h.version,
                    "cpu_count": h.cpu_count, "memory_gb": h.memory_gb, "uptime_days": h.uptime_days,
                    "worst_disk": worst.mount if worst else "", "worst_disk_pct": worst.used_pct if worst else "",
                    "reachable": h.reachable, "error": h.error,
                })
