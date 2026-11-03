# shellcheck shell=bash
# Rotation of the local backup sets: daily ones for KEEP_DAILY days, a weekly
# copy (made on Sundays) kept for KEEP_WEEKLY weeks.

rotate_daily() {
    local dest="$1" keep="$2"
    local removed
    removed=$(find "$dest/daily" -mindepth 1 -maxdepth 1 -type d -mtime +"$keep" -print | wc -l)
    find "$dest/daily" -mindepth 1 -maxdepth 1 -type d -mtime +"$keep" -exec rm -rf -- {} +
    info "rotate: removed $removed daily set(s) older than $keep days"
}

rotate_weekly() {
    local dest="$1" keep="$2"
    local keep_days=$(( keep * 7 ))
    find "$dest/weekly" -mindepth 1 -maxdepth 1 -type d -mtime +"$keep_days" -exec rm -rf -- {} +
    info "rotate: weekly sets older than $keep weeks removed"
}

# On Sundays, the day's set is also kept as the week's.
promote_weekly() {
    local dest="$1" set_dir="$2"
    if [[ "$(date +%u)" == "7" ]]; then
        mkdir -p "$dest/weekly"
        cp -al -- "$set_dir" "$dest/weekly/$(basename "$set_dir")"
        info "rotate: $(basename "$set_dir") kept as this week's set"
    fi
}

rotate_all() {
    local dest="$1"
    rotate_daily "$dest" "$KEEP_DAILY"
    rotate_weekly "$dest" "$KEEP_WEEKLY"
}

# Old scheme (one tarball per day in $dest, no folders). Kept until the last
# servers are moved over; nothing calls it any more.
rotate_flat_tarballs() {
    local dest="$1" keep="$2"
    ls -1t "$dest"/*.tar.gz 2>/dev/null | tail -n +"$((keep + 1))" | xargs -r rm -f --
}
