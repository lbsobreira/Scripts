#!/usr/bin/env bash
#
# check_services.sh - local health checks with Nagios-style exit codes
# (0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN). Alerts on state change.
#
#   check_services.sh [-c health-check.conf] [-e endpoints.json] [-q]
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="$HERE/health-check.conf"
ENDPOINTS="$HERE/endpoints.json"
QUIET=0

OK=0; WARNING=1; CRITICAL=2; UNKNOWN=3
STATUS=$OK
declare -a REPORT=()

# shellcheck source=alert.sh
source "$HERE/alert.sh"

while getopts ":c:e:q" opt; do
    case "$opt" in
        c) CONF="$OPTARG" ;;
        e) ENDPOINTS="$OPTARG" ;;
        q) QUIET=1 ;;
        *) echo "usage: $0 [-c conf] [-e endpoints.json] [-q]" >&2; exit $UNKNOWN ;;
    esac
done

[[ -r "$CONF" ]] || { echo "UNKNOWN: cannot read $CONF"; exit $UNKNOWN; }
# shellcheck disable=SC1090
source "$CONF"

# Keep the worst status seen, and a line for the report.
raise() {
    local level="$1"; shift
    (( level > STATUS )) && STATUS=$level
    REPORT+=("$*")
}

check_disk() {
    local use mount
    while read -r use mount; do
        use="${use%\%}"
        if (( use >= DISK_CRIT )); then
            raise $CRITICAL "disk $mount at ${use}%"
        elif (( use >= DISK_WARN )); then
            raise $WARNING "disk $mount at ${use}%"
        fi
    done < <(df -P -x tmpfs -x devtmpfs -x squashfs | awk 'NR>1 {print $5, $6}')
}

check_load() {
    local cpus load1
    cpus="$(nproc)"
    load1="$(cut -d' ' -f1 /proc/loadavg)"
    if awk -v l="$load1" -v c="$cpus" -v t="$LOAD_CRIT_PER_CPU" 'BEGIN { exit !(l > c * t) }'; then
        raise $CRITICAL "load $load1 on $cpus CPUs"
    elif awk -v l="$load1" -v c="$cpus" -v t="$LOAD_WARN_PER_CPU" 'BEGIN { exit !(l > c * t) }'; then
        raise $WARNING "load $load1 on $cpus CPUs"
    fi
}

check_units() {
    local unit state
    for unit in $UNITS; do
        # A unit that is not installed here is not a problem.
        systemctl list-unit-files "$unit.service" --no-legend | grep -q . || continue
        state="$(systemctl is-active "$unit" 2>/dev/null)"
        if [[ "$state" != "active" ]]; then
            raise $CRITICAL "service $unit is $state"
        fi
    done
}

cert_days_left() {
    local host="$1" port="${2:-443}"
    local end
    end="$(echo | timeout 10 openssl s_client -servername "$host" -connect "$host:$port" 2>/dev/null \
        | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)"
    [[ -n "$end" ]] || { echo -1; return; }
    echo $(( ( $(date -d "$end" +%s) - $(date +%s) ) / 86400 ))
}

check_endpoint() {
    local name="$1" url="$2" expect="$3" cert="$4"
    local status host days

    if ! status="$(curl -fsS -m 15 "$url" | jq -r '.status // empty' 2>/dev/null)"; then
        raise $CRITICAL "$name: $url does not answer"
        return
    fi
    if [[ "$expect" != "null" && "$status" != "$expect" ]]; then
        raise $WARNING "$name: status '$status', expected '$expect'"
    fi

    if [[ "$cert" == "true" ]]; then
        host="$(echo "$url" | sed -E 's#^https://([^/:]+).*#\1#')"
        days="$(cert_days_left "$host")"
        if (( days < 0 )); then
            raise $UNKNOWN "$name: could not read the certificate of $host"
        elif (( days <= CERT_CRIT_DAYS )); then
            raise $CRITICAL "$name: certificate of $host expires in $days days"
        elif (( days <= CERT_WARN_DAYS )); then
            raise $WARNING "$name: certificate of $host expires in $days days"
        fi
    fi
}

check_endpoints() {
    local item name url expect cert
    [[ -r "$ENDPOINTS" ]] || { raise $UNKNOWN "cannot read $ENDPOINTS"; return; }
    while read -r item; do
        name="$(jq -r '.name' <<< "$item")"
        url="$(jq -r '.url' <<< "$item")"
        expect="$(jq -r '.expect' <<< "$item")"
        cert="$(jq -r '.cert' <<< "$item")"
        check_endpoint "$name" "$url" "$expect" "$cert"
    done < <(jq -c '.[]' "$ENDPOINTS")
}

check_extra() {
    [[ -n "${EXTRA_CHECK:-}" ]] || return 0
    if ! eval "$EXTRA_CHECK"; then
        raise $WARNING "extra check failed: $EXTRA_CHECK"
    fi
}

# Old load check from before /proc/loadavg was used; left for reference.
check_uptime_load() {
    uptime | awk -F'load average: ' '{print $2}' | cut -d, -f1
}

# Called by the trap below if the script is killed (run-from-cron.sh uses timeout).
on_terminate() {
    echo "UNKNOWN: health check interrupted"
    send_alert UNKNOWN "health check interrupted" "check_services.sh was stopped before it finished"
    exit $UNKNOWN
}
trap on_terminate TERM INT

for name in $CHECKS; do
    cmd="check_$name"
    if declare -F "$cmd" >/dev/null; then
        $cmd
    else
        raise $UNKNOWN "no such check: $name"
    fi
done
check_extra

labels=(OK WARNING CRITICAL UNKNOWN)
summary="${labels[$STATUS]}: ${#REPORT[@]} problem(s)"
if (( ${#REPORT[@]} )); then
    body="$(printf '%s\n' "${REPORT[@]}")"
else
    body="all checks passed"
fi

(( QUIET )) || { echo "$summary"; echo "$body"; }

if (( STATUS != OK )); then
    send_alert "${labels[$STATUS]}" "health on $(hostname -s)" "$body"
fi
exit $STATUS
