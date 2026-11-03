"""Builds squid.conf from the template and the ACL sections."""

import logging
from pathlib import Path
from string import Template

from squid_setup.acl.acls import build_acls, build_access_rules
from squid_setup.acl.dstdomains import load_dstdomains
from squid_setup.network.allowed_hosts import load_allowed_hosts
from squid_setup.network.ports import load_ports

log = logging.getLogger(__name__)

TEMPLATE = Path(__file__).with_name("squid.conf.tmpl")


def build_config(lists_dir: Path, listen_port: int = 3128) -> str:
    hosts = load_allowed_hosts(lists_dir / "allowed_hosts.txt")
    domains = load_dstdomains(lists_dir / "dstdomains.txt")
    ports = load_ports(lists_dir / "ports.txt")
    log.info("%d client networks, %d domains, %d ports", len(hosts), len(domains), len(ports))

    acl_lines = build_acls(hosts, domains, ports)
    access_lines = build_access_rules()

    template = Template(TEMPLATE.read_text())
    return template.substitute(
        listen_port=listen_port,
        acls="\n".join(acl_lines),
        access_rules="\n".join(access_lines),
    )
