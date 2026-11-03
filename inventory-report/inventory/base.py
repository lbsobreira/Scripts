"""The collector every kind of host shares."""

import abc
import logging
import time

from .models import Host

log = logging.getLogger(__name__)


class CollectorError(Exception):
    pass


class Collector(abc.ABC):
    """Asks one host for its facts. Subclasses implement collect()."""

    kind = "?"

    def __init__(self, settings):
        self.settings = settings
        self.timeout = settings.timeout

    @abc.abstractmethod
    def collect(self, entry: dict) -> dict:
        """Returns the raw facts of the host named in `entry`."""

    def run(self, entry: dict) -> Host:
        started = time.monotonic()
        raw = self.collect(entry)
        host = self._normalise(entry["name"], raw)
        log.debug("%s collected in %.1fs", entry["name"], time.monotonic() - started)
        return host

    def _normalise(self, name: str, raw: dict) -> Host:
        return Host(
            name=name,
            kind=self.kind,
            os=raw.get("os", ""),
            version=raw.get("version", ""),
            cpu_count=int(raw.get("cpu_count", 0)),
            memory_gb=round(float(raw.get("memory_bytes", 0)) / 2**30, 1),
            uptime_days=round(float(raw.get("uptime_s", 0)) / 86400, 1),
            disks=raw.get("disks", []),
        )
