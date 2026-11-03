# shellcheck shell=bash
# Shared helpers for backup.sh and restore.sh. Source it, do not run it.

# Where log lines go. backup.conf can override it; keep a default so restore.sh
# works without a config.
LOG_FILE="${LOG_FILE:-/var/log/backup-rotate.log}"
LOG_TAG="${LOG_TAG:-backup-rotate}"
VERBOSE="${VERBOSE:-0}"

timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

log() {
    local level="$1"; shift
    local line
    line="$(timestamp) [$level] $*"
    # Always to the log file; to the terminal only when someone is watching.
    printf '%s\n' "$line" >> "$LOG_FILE"
    if [[ -t 1 || "$VERBOSE" == "1" ]]; then
        printf '%s\n' "$line"
    fi
    # Errors also go to syslog so the monitoring picks them up.
    if [[ "$level" == "ERROR" ]]; then
        logger -t "$LOG_TAG" -p user.err -- "$*"
    fi
}

info()  { log INFO "$@"; }
warn()  { log WARN "$@"; }

die() {
    log ERROR "$@"
    exit 1
}

require_cmd() {
    local cmd
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || die "required command not found: $cmd"
    done
}

# Human readable size of a file or folder, for the log.
human_size() {
    du -sh -- "$1" 2>/dev/null | cut -f1
}

# Check there is room for a backup before starting it.
check_free_space() {
    local dir="$1" need_mb="$2"
    local free_mb
    free_mb=$(df -Pm -- "$dir" | awk 'NR==2 {print $4}')
    if (( free_mb < need_mb )); then
        die "only ${free_mb} MB free in $dir, need ${need_mb} MB"
    fi
    info "free space in $dir: ${free_mb} MB"
}

# Run a command, log it, and stop on failure. Used for the steps that matter.
run_logged() {
    info "running: $*"
    if ! "$@" 2>>"$LOG_FILE"; then
        die "command failed: $*"
    fi
}
