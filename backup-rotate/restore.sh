#!/usr/bin/env bash
#
# restore.sh - restore files or a database from a backup set.
#
#   restore.sh list
#   restore.sh files <YYYY-MM-DD> <archive-name> [target-dir]
#   restore.sh db <YYYY-MM-DD> <database>
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

CONF="${CONFIG:-/etc/backup-rotate/backup.conf}"
[[ -r "$CONF" ]] || CONF="$SCRIPT_DIR/backup.conf"
source "$CONF"

verify_set() {
    local set_dir="$1"
    [[ -d "$set_dir" ]] || die "no backup set $set_dir"
    ( cd "$set_dir" && sha256sum --quiet -c MANIFEST.sha256 ) \
        || die "checksum mismatch in $set_dir"
    info "restore: $set_dir verified"
}

list_sets() {
    local d
    for d in "$BACKUP_DEST"/daily/* "$BACKUP_DEST"/weekly/*; do
        [[ -d "$d" ]] || continue
        printf '%-40s %s\n' "$d" "$(human_size "$d")"
    done
}

restore_files() {
    local day="$1" archive="$2" target="${3:-/var/tmp/restore-$1}"
    local set_dir="$BACKUP_DEST/daily/$day"
    verify_set "$set_dir"
    mkdir -p "$target"
    info "restore: $archive from $day into $target"
    run_logged tar -xzpf "$set_dir/$archive" -C "$target"
}

restore_db() {
    local day="$1" db="$2"
    local set_dir="$BACKUP_DEST/daily/$day"
    verify_set "$set_dir"
    require_cmd pg_restore
    read -r -p "This replaces database '$db' on $(hostname -s). Type its name to go on: " answer
    [[ "$answer" == "$db" ]] || die "restore cancelled"
    gunzip -c "$set_dir/pg-$db.dump.gz" \
        | sudo -u "$PG_USER" pg_restore --clean --if-exists -d "$db"
    info "restore: database $db restored from $day"
}

case "${1:-}" in
    list)  list_sets ;;
    files) shift; restore_files "$@" ;;
    db)    shift; restore_db "$@" ;;
    *)     sed -n '3,8p' "$0"; exit 2 ;;
esac
