#!/usr/bin/env bash
# post-install.sh <role> - checks after bootstrap and a summary for the ticket.
set -uo pipefail

role="${1:-unknown}"
problems=0

check() {
    local what="$1"; shift
    if "$@" >/dev/null 2>&1; then
        printf '  [ok]   %s\n' "$what"
    else
        printf '  [FAIL] %s\n' "$what"
        problems=$((problems + 1))
    fi
}

echo "Post-install checks for role '$role' on $(hostname -f)"
check "sshd config valid"          sshd -t
check "time is synchronised"       timedatectl show -p NTPSynchronized --value
check "no failed units"            test "$(systemctl --failed --no-legend | wc -l)" -eq 0

case "$role" in
    web)     check "nginx answers"         curl -fsS -o /dev/null http://localhost/ ;;
    db)      check "postgres accepts"      pg_isready -q ;;
    monitor) check "prometheus is ready"   curl -fsS http://localhost:9090/-/ready ;;
esac

echo
echo "IP addresses: $(hostname -I)"
echo "Kernel:       $(uname -r)"
exit "$problems"
