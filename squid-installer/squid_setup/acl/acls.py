"""The acl and http_access lines of squid.conf."""

from squid_setup.network.ports import format_port_acl

SAFE_PORTS = "Safe_ports"
SSL_PORTS = "SSL_ports"


def build_acls(hosts, domains, ports):
    lines = ["# Clients allowed to use the proxy"]
    lines += [f"acl allowed_hosts src {net}" for net in hosts]

    lines.append("")
    lines.append("# Destinations they may reach")
    lines += [f"acl allowed_domains dstdomain {domain}" for domain in domains]

    lines.append("")
    lines.append("# Ports")
    lines += format_port_acl(SAFE_PORTS, ports)
    lines += format_port_acl(SSL_PORTS, [p for p in ports if p in (443, 8443)])
    lines.append("acl CONNECT method CONNECT")
    return lines


def build_access_rules():
    return [
        f"http_access deny !{SAFE_PORTS}",
        f"http_access deny CONNECT !{SSL_PORTS}",
        "http_access allow localhost manager",
        "http_access deny manager",
        "http_access allow allowed_hosts allowed_domains",
        "http_access deny all",
    ]
