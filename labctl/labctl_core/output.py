"""Plain-text tables and messages for the terminal."""

import shutil
import sys


def print_table(rows, columns):
    """Prints dicts as an aligned table. `columns` is a list of (key, heading)."""
    if not rows:
        print("(none)")
        return
    widths = [len(h) for _, h in columns]
    for row in rows:
        for i, (key, _) in enumerate(columns):
            widths[i] = max(widths[i], len(str(row.get(key, ""))))
    term = shutil.get_terminal_size((120, 20)).columns
    line = "  ".join(h.ljust(w) for (_, h), w in zip(columns, widths))
    print(line[:term])
    print("  ".join("-" * w for w in widths)[:term])
    for row in rows:
        print("  ".join(str(row.get(k, "")).ljust(w) for (k, _), w in zip(columns, widths))[:term])


def ok(message: str):
    print(f"OK  {message}")


def warn(message: str):
    print(f"!!  {message}", file=sys.stderr)


def confirm(question: str) -> bool:
    if not sys.stdin.isatty():
        return False
    return input(f"{question} [y/N] ").strip().lower() in ("y", "yes")
