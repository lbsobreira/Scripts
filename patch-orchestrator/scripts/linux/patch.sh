#!/usr/bin/env bash
# Patches this host. Exit 100 when it needs a reboot afterwards.
#   sudo bash patch.sh --yes
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PATCH_LOG="${PATCH_LOG:-/var/log/patching.log}"
HOLD="${PATCH_HOLD:-docker-ce containerd.io}"

source "$HERE/lib.sh"

[[ ${1:-} == --yes ]] || die "refusing to patch without --yes"
[[ $EUID -eq 0 ]] || die "run as root"

pm=$(detect_pm)
log "patching $(hostname) with $pm"

# shellcheck disable=SC2086
hold_packages "$pm" $HOLD

case $pm in
    apt)
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -q
        apt-get -y -q -o Dpkg::Options::=--force-confold dist-upgrade
        apt-get -y -q autoremove
        ;;
    dnf)
        dnf -y -q upgrade --refresh
        ;;
esac

log "packages done"

if python3 "$(dirname "$0")/../reboot_check.py"; then
    log "no reboot needed"
    exit 0
else
    rc=$?
    [[ $rc -eq 100 ]] || die "reboot_check.py failed ($rc)"
    log "reboot needed"
    exit 100
fi
