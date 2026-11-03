"""labctl backup run"""

import logging
from datetime import datetime

from ..output import print_table, ok, warn

log = logging.getLogger(__name__)


def run_backup(args):
    target = args.target or args.cfg.backup_target
    keep = args.keep if args.keep is not None else args.cfg.backup_keep
    log.info("backup to %s, keeping %d", target, keep)

    job = args.client.post("/backups", {"target": target, "keep": keep})
    result = args.client.wait_for_job(job["id"], timeout=3600)
    if result["state"] != "done":
        warn(f"backup failed: {result.get('error')}")
        return 1

    points = args.client.get(f"/backups/{target}/points")
    print_table(points, [("vm", "VM"), ("created", "CREATED"), ("size_gb", "SIZE GB")])
    ok(f"backup to {target} finished")


def _prune_local(points, keep):
    """Old client-side pruning; the server prunes since API v1.3."""
    points = sorted(points, key=lambda p: datetime.fromisoformat(p["created"]), reverse=True)
    return points[keep:]
