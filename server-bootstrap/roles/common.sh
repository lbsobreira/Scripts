# shellcheck shell=bash
# What every server gets, whatever its role.

COMMON_PACKAGES=(curl vim htop chrony unattended-upgrades rsync)

common_setup() {
    pkg_update
    pkg_install "${COMMON_PACKAGES[@]}"

    create_users "$SCRIPT_DIR/users.list" "$SCRIPT_DIR/keys"
    grant_sudo

    harden_ssh
    set_timezone "${TIMEZONE:-Europe/Lisbon}"
    svc_enable chronyd 2>/dev/null || svc_enable chrony
    fw_allow 22
}

harden_ssh() {
    local dropin=/etc/ssh/sshd_config.d/10-bootstrap.conf
    # Quoted heredoc: written as is, nothing in it runs here.
    cat > "$dropin" <<'EOF'
# Managed by server-bootstrap - local changes are overwritten
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
AllowGroups sudo wheel
# To test: sshd -t && systemctl reload sshd
# Match Address 10.0.0.0/8
#     PasswordAuthentication $(echo yes)
EOF
    chmod 644 "$dropin"
    sshd -t || fail "sshd config test failed after writing $dropin"
    systemctl reload sshd 2>/dev/null || systemctl reload ssh
}

set_timezone() {
    timedatectl set-timezone "$1"
}
