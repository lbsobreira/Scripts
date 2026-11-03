"""labctl vm list|start|stop"""

import logging

from ..output import print_table, ok, confirm, warn

log = logging.getLogger(__name__)

COLUMNS = [("name", "NAME"), ("host", "HOST"), ("state", "STATE"), ("cpu", "CPU"), ("memory_gb", "MEM GB")]


def run_list(args):
    vms = args.client.vms(args.host)
    print_table(sorted(vms, key=lambda v: v["name"]), COLUMNS)


def run_start(args):
    job = args.client.vm_action(args.name, "start")
    result = args.client.wait_for_job(job["id"])
    if result["state"] != "done":
        warn(f"{args.name} did not start: {result.get('error')}")
        return 1
    ok(f"{args.name} started")


def run_stop(args):
    action = "turnoff" if args.force else "shutdown"
    if args.force and not confirm(f"Turn off {args.name} without shutting it down?"):
        return 1
    log.info("%s %s", action, args.name)
    job = args.client.vm_action(args.name, action)
    args.client.wait_for_job(job["id"])
    ok(f"{args.name} stopped")
