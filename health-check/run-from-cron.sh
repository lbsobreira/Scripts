#!/bin/bash
# Cron wrapper for check_services.sh: a sane PATH, one run at a time, a hard
# time limit, and the output in a log instead of cron mail.

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

# The webhook lives outside the repo; cron does not read the user's profile.
if [[ -r /etc/health-check/env ]]; then
    set -a
    # shellcheck disable=SC1091
    . /etc/health-check/env
    set +a
fi

LOG_DIR=/var/log/health-check
mkdir -p "$LOG_DIR"

exec >>"$LOG_DIR/health-check.log" 2>&1
echo "=== $(date -Is)"

exec flock -n /run/lock/health-check.lock \
    timeout --signal=TERM 240 \
    /opt/health-check/check_services.sh -q "$@"
