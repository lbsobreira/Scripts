"""Reads the plain-text lists: one entry per line, # for comments."""

from pathlib import Path


def read_list(path: Path) -> list[str]:
    entries = []
    for line in path.read_text().splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            entries.append(line)
    return entries
