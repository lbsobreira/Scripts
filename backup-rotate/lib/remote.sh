# shellcheck shell=bash
# Copy of the day's set to the offsite host (OFFSITE_HOST in backup.conf).

remote_ssh() {
    ssh -i "$OFFSITE_KEY" -o BatchMode=yes -o ConnectTimeout=10 \
        "${OFFSITE_USER}@${OFFSITE_HOST}" "$@"
}

push_offsite() {
    local set_dir="$1"
    local name
    name="$(basename "$set_dir")"

    if [[ -z "${OFFSITE_HOST:-}" ]]; then
        warn "offsite: OFFSITE_HOST not set, skipping the offsite copy"
        return 0
    fi

    info "offsite: copying $name to ${OFFSITE_HOST}:${OFFSITE_PATH}"
    remote_ssh "mkdir -p '${OFFSITE_PATH}/daily'" || die "offsite: cannot reach $OFFSITE_HOST"

    rsync -a --delete --partial \
        -e "ssh -i $OFFSITE_KEY -o BatchMode=yes" \
        --bwlimit="${OFFSITE_BWLIMIT:-0}" \
        -- "$set_dir/" "${OFFSITE_USER}@${OFFSITE_HOST}:${OFFSITE_PATH}/daily/$name/" \
        || die "offsite: rsync to $OFFSITE_HOST failed"

    # The offsite host keeps its own number of days.
    remote_ssh "find '${OFFSITE_PATH}/daily' -mindepth 1 -maxdepth 1 -type d -mtime +${OFFSITE_KEEP_DAILY} -exec rm -rf {} +"
    info "offsite: done"
}
