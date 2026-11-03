#!/usr/bin/env bash
#
# backup.sh - nightly backup of files and PostgreSQL databases, with rotation
# and an optional offsite copy.
#
# Usage: backup.sh [-c config] [-n] [-v] [-s]
#   -c FILE  config file (default: $CONFIG, then /etc/backup-rotate/backup.conf,
#            then backup.conf next to this script)
#   -n       dry run: show what would be backed up, change nothing
#   -v       verbose (log to the terminal as well)
#   -s       skip the offsite copy
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/lib/common.sh"
. "${SCRIPT_DIR}/lib/rotate.sh"
source "$SCRIPT_DIR/lib/remote.sh"

DRY_RUN=0
SKIP_OFFSITE=0
LOCK_FILE=/run/lock/backup-rotate.lock
WORK_DIR=""

usage() {
    sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while getopts ":c:nvsh" opt; do
    case "$opt" in
        c) CONFIG="$OPTARG" ;;
        n) DRY_RUN=1 ;;
        v) VERBOSE=1 ;;
        s) SKIP_OFFSITE=1 ;;
        h) usage 0 ;;
        :) echo "option -$OPTARG needs a value" >&2; usage 2 ;;
        \?) echo "unknown option -$OPTARG" >&2; usage 2 ;;
    esac
done
shift $((OPTIND - 1))

# Config: -c, then $CONFIG, then the system one, then the copy next to us.
if [[ -r "${CONFIG:-/etc/backup-rotate/backup.conf}" ]]; then
    source "${CONFIG:-/etc/backup-rotate/backup.conf}"
elif [[ -r "$SCRIPT_DIR/backup.conf" ]]; then
    source "$SCRIPT_DIR/backup.conf"
else
    echo "no config found" >&2
    exit 1
fi

# The excludes next to the script when the system one is not there.
if [[ ! -r "$EXCLUDES_FILE" ]]; then
    EXCLUDES_FILE="$SCRIPT_DIR/excludes.txt"
fi

cleanup() {
    local rc=$?
    if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
        rm -rf -- "$WORK_DIR"
    fi
    if (( rc != 0 )); then
        log ERROR "backup finished with errors (exit $rc)"
    fi
}
trap cleanup EXIT

backup_files() {
    local set_dir="$1"
    local src name
    read -r -a sources <<< "$BACKUP_SOURCES"
    for src in "${sources[@]}"; do
        if [[ ! -e "$src" ]]; then
            warn "files: $src does not exist, skipped"
            continue
        fi
        name="$(echo "$src" | sed 's#^/##; s#/#_#g')"
        info "files: $src -> $name.tar.gz"
        tar --exclude-from="$EXCLUDES_FILE" --one-file-system -cpf - -- "$src" 2>>"$LOG_FILE" \
            | gzip -6 > "$set_dir/$name.tar.gz"
        info "files: $name.tar.gz $(human_size "$set_dir/$name.tar.gz")"
    done
}

backup_databases() {
    local set_dir="$1"
    local db
    if [[ -z "$PG_DATABASES" ]]; then
        info "db: no databases configured"
        return 0
    fi
    require_cmd pg_dump
    for db in $PG_DATABASES; do
        info "db: dumping $db"
        sudo -u "$PG_USER" pg_dump --format=custom --compress=0 "$db" \
            | gzip -6 > "$set_dir/pg-$db.dump.gz" \
            || die "db: pg_dump of $db failed"
    done
    # Roles and grants, which pg_dump does not include.
    sudo -u "$PG_USER" pg_dumpall --globals-only | gzip > "$set_dir/pg-globals.sql.gz"
}

write_manifest() {
    local set_dir="$1"
    (
        cd "$set_dir"
        sha256sum -- * > MANIFEST.sha256
    )
    info "manifest: $(wc -l < "$set_dir/MANIFEST.sha256") files"
}

main() {
    require_cmd tar gzip rsync flock sha256sum

    exec 9>"$LOCK_FILE"
    if ! flock -n 9; then
        die "another backup is running (lock $LOCK_FILE)"
    fi

    local today set_dir
    today="$(date +%Y-%m-%d)"
    set_dir="$BACKUP_DEST/daily/$today"

    if (( DRY_RUN )); then
        info "dry run: would back up '$BACKUP_SOURCES' and databases '${PG_DATABASES:-none}' to $set_dir"
        return 0
    fi

    mkdir -p "$BACKUP_DEST/daily"
    check_free_space "$BACKUP_DEST" "$MIN_FREE_MB"

    WORK_DIR="$(mktemp -d "$BACKUP_DEST/.incoming.XXXXXX")"
    info "backup of $(hostname -f) started into $set_dir"

    backup_files "$WORK_DIR"
    backup_databases "$WORK_DIR"
    write_manifest "$WORK_DIR"

    rm -rf -- "$set_dir"
    mv -- "$WORK_DIR" "$set_dir"
    WORK_DIR=""

    promote_weekly "$BACKUP_DEST" "$set_dir"
    rotate_all "$BACKUP_DEST"

    if (( ! SKIP_OFFSITE )); then
        push_offsite "$set_dir"
    fi

    info "backup finished: $(human_size "$set_dir") in $set_dir"
}

main "$@"
