"""What the report holds about a host."""

from dataclasses import dataclass, field
from datetime import datetime


@dataclass
class Disk:
    mount: str
    size_gb: float
    free_gb: float

    @property
    def used_pct(self) -> float:
        return 0.0 if not self.size_gb else round(100 * (1 - self.free_gb / self.size_gb), 1)


@dataclass
class Host:
    name: str
    kind: str
    os: str = ""
    version: str = ""
    cpu_count: int = 0
    memory_gb: float = 0.0
    uptime_days: float = 0.0
    disks: list[Disk] = field(default_factory=list)
    reachable: bool = True
    error: str = ""
    collected_at: datetime = field(default_factory=datetime.now)

    @classmethod
    def unreachable(cls, name: str, error: str) -> "Host":
        return cls(name=name, kind="?", reachable=False, error=error)

    def worst_disk(self):
        return max(self.disks, key=lambda d: d.used_pct, default=None)
