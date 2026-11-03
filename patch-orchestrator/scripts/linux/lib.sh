# Shared functions for the Linux patch scripts. Sourced, not run.

log() {
    printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$PATCH_LOG"
}

die() {
    log "ERROR: $*"
    exit 1
}

detect_pm() {
    if command -v apt-get >/dev/null 2>&1; then
        echo apt
    elif command -v dnf >/dev/null 2>&1; then
        echo dnf
    else
        die "no supported package manager"
    fi
}

hold_packages() {
    # Packages we never upgrade during a patch window (see HOLD in patch.sh).
    local pm=$1; shift
    for pkg in "$@"; do
        case $pm in
            apt) apt-mark hold "$pkg" >/dev/null ;;
            dnf) dnf versionlock add "$pkg" >/dev/null ;;
        esac
        log "held $pkg"
    done
}
