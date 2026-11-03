# shellcheck shell=bash
# send_alert <severity> <subject> <body>
# Posts to the chat webhook in $ALERT_WEBHOOK; when that is not set or fails,
# mails $ALERT_MAILTO instead.

ALERT_MAILTO="${ALERT_MAILTO:-ops@lab.example}"
ALERT_STATE_DIR="${ALERT_STATE_DIR:-/var/lib/health-check}"

json_escape() {
    jq -Rs . <<< "$1"
}

send_webhook() {
    local text="$1"
    curl -fsS -m 10 -X POST -H 'Content-Type: application/json' \
        --data "{\"text\": $(json_escape "$text")}" \
        "$ALERT_WEBHOOK" >/dev/null
}

send_mail() {
    local subject="$1" body="$2"
    printf '%s\n' "$body" | mail -s "$subject" "$ALERT_MAILTO"
}

# Only alert when the state changes, so cron does not send the same thing
# every five minutes.
state_changed() {
    local key="$1" state="$2" file
    file="$ALERT_STATE_DIR/$key.state"
    mkdir -p "$ALERT_STATE_DIR"
    if [[ -f "$file" && "$(cat "$file")" == "$state" ]]; then
        return 1
    fi
    echo "$state" > "$file"
    return 0
}

send_alert() {
    local severity="$1" subject="$2" body="$3"
    local text="[$severity] $(hostname -s): $subject"$'\n'"$body"

    state_changed "$(echo "$subject" | tr -c 'a-zA-Z0-9' '_')" "$severity" || return 0

    if [[ -n "${ALERT_WEBHOOK:-}" ]] && send_webhook "$text"; then
        return 0
    fi
    send_mail "[$severity] $(hostname -s): $subject" "$body"
}
