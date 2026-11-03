"""Destination domains the clients may reach."""

import re
from pathlib import Path

from squid_setup.common.listfile import read_list

_DOMAIN = re.compile(r"^\.?([a-z0-9-]+\.)+[a-z]{2,}$")


def load_dstdomains(path: Path) -> list[str]:
    domains = []
    for entry in read_list(path):
        entry = entry.lower()
        if not _DOMAIN.match(entry):
            raise ValueError(f"{path}: not a domain: {entry!r}")
        domains.append(entry)
    return _drop_covered(domains)


def _drop_covered(domains):
    """'.example.org' already covers 'www.example.org'; squid refuses both."""
    wildcards = [d for d in domains if d.startswith(".")]
    kept = []
    for d in sorted(set(domains)):
        if any(d != w and (d.endswith(w) or d == w[1:]) for w in wildcards):
            continue
        kept.append(d)
    return kept
