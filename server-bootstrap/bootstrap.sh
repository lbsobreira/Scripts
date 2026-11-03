#!/usr/bin/env bash
#
# bootstrap.sh - first setup of a new server: packages, admin users, SSH
# hardening, firewall, then the role (web, db or monitor).
#
#   sudo ./bootstrap.sh --role web [--hostname web01.lab.example] [--no-post]
#
# Environment: TIMEZONE (default Europe/Lisbon), SITE_NAME / WEB_ROOT (web),
# PG_LISTEN / PG_ALLOW_NET (db), PROM_RETENTION (monitor).
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG=/var/log/bootstrap.log
ROLE=""
NEW_HOSTNAME=""
RUN_POST=1

msg()  { echo "[bootstrap] $*" | tee -a "$LOG"; }
fail() { echo "[bootstrap] ERROR: $*" | tee -a "$LOG" >&2; exit 1; }

detect_os() {
    [[ -r /etc/os-release ]] || fail "cannot read /etc/os-release"
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID_LIKE:-$ID}" in
        *debian*|*ubuntu*) OS_FAMILY=debian ;;
        *rhel*|*fedora*|*centos*) OS_FAMILY=rhel ;;
        *) fail "unsupported distribution: ${PRETTY_NAME:-$ID}" ;;
    esac
    msg "detected $PRETTY_NAME ($OS_FAMILY)"
}

parse_args() {
    while (( $# )); do
        case "$1" in
            --role)     ROLE="${2:?--role needs a value}"; shift 2 ;;
            --hostname) NEW_HOSTNAME="${2:?}"; shift 2 ;;
            --no-post)  RUN_POST=0; shift ;;
            -h|--help)  sed -n '3,10p' "$0"; exit 0 ;;
            *)          fail "unknown argument: $1" ;;
        esac
    done
    case "$ROLE" in
        web|db|monitor) ;;
        "") fail "--role is required (web, db or monitor)" ;;
        *)  fail "unknown role '$ROLE'" ;;
    esac
}

set_hostname() {
    [[ -n "$NEW_HOSTNAME" ]] || return 0
    hostnamectl set-hostname "$NEW_HOSTNAME"
    if ! grep -q "$NEW_HOSTNAME" /etc/hosts; then
        echo "127.0.1.1 $NEW_HOSTNAME ${NEW_HOSTNAME%%.*}" >> /etc/hosts
    fi
    msg "hostname set to $NEW_HOSTNAME"
}

main() {
    [[ $EUID -eq 0 ]] || fail "run as root (sudo)"
    parse_args "$@"
    : > "$LOG"
    detect_os
    export OS_FAMILY

    source "$SCRIPT_DIR/lib/pkg.sh"
    source "$SCRIPT_DIR/lib/users.sh"
    source "$SCRIPT_DIR/roles/common.sh"

    set_hostname
    common_setup

    local role_file="$SCRIPT_DIR/roles/$ROLE.sh"
    [[ -r "$role_file" ]] || fail "no role file $role_file"
    # shellcheck disable=SC1090
    source "$role_file"
    msg "role $ROLE: $(role_packages | tr '\n' ' ')"
    role_setup

    if (( RUN_POST )); then
        bash "$SCRIPT_DIR/post-install.sh" "$ROLE" | tee -a "$LOG"
    fi
    msg "done; log in $LOG"
}

main "$@"
