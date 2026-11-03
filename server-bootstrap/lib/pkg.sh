# shellcheck shell=bash
# Package manager wrapper: apt on Debian/Ubuntu, dnf on RHEL/Rocky/Alma.
# Needs OS_FAMILY (set by bootstrap.sh from /etc/os-release).

pkg_update() {
    case "$OS_FAMILY" in
        debian) DEBIAN_FRONTEND=noninteractive apt-get update -qq ;;
        rhel)   dnf -q makecache ;;
    esac
}

pkg_install() {
    (( $# )) || return 0
    msg "installing: $*"
    case "$OS_FAMILY" in
        debian) DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "$@" ;;
        rhel)   dnf install -y -q "$@" ;;
        *)      fail "pkg_install: unsupported OS family '$OS_FAMILY'" ;;
    esac
}

pkg_is_installed() {
    case "$OS_FAMILY" in
        debian) dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "ok installed" ;;
        rhel)   rpm -q "$1" >/dev/null 2>&1 ;;
    esac
}

# Package names differ between the families; map the Debian name to the RHEL one.
pkg_name() {
    local name="$1"
    if [[ "$OS_FAMILY" == "rhel" ]]; then
        case "$name" in
            apache2)          name=httpd ;;
            postgresql)       name=postgresql-server ;;
            prometheus-node-exporter) name=node_exporter ;;
        esac
    fi
    printf '%s\n' "$name"
}

# Turn on and start a service, whatever it is called on this family.
svc_enable() {
    local unit="$1"
    systemctl enable --now "$unit"
    systemctl is-active --quiet "$unit" || fail "service $unit did not start"
}

# Open a port in whichever firewall this host has.
fw_allow() {
    local port="$1" proto="${2:-tcp}"
    if command -v ufw >/dev/null 2>&1; then
        ufw allow "${port}/${proto}"
    elif command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port="${port}/${proto}"
        firewall-cmd --reload
    else
        msg "no firewall tool found; port $port/$proto not opened"
    fi
}
