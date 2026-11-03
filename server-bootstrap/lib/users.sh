# shellcheck shell=bash
# Admin accounts from users.list and their SSH keys from keys/<user>.pub.

# users.list format:  user:uid:groups:comment   (# for comments)
create_users() {
    local list="$1" keydir="$2"
    local user uid groups comment
    while IFS=: read -r user uid groups comment; do
        [[ -z "$user" || "$user" == \#* ]] && continue
        if id "$user" >/dev/null 2>&1; then
            msg "user $user exists"
        else
            useradd --create-home --shell /bin/bash --uid "$uid" \
                --comment "$comment" "$user"
            msg "user $user created (uid $uid)"
        fi
        if [[ -n "$groups" ]]; then
            usermod -aG "$groups" "$user"
        fi
        install_keys "$user" "$keydir/$user.pub"
    done < "$list"
}

install_keys() {
    local user="$1" keyfile="$2"
    local home
    if [[ ! -r "$keyfile" ]]; then
        msg "no key for $user ($keyfile)"
        return 0
    fi
    home="$(getent passwd "$user" | cut -d: -f6)"
    install -d -m 700 -o "$user" -g "$user" "$home/.ssh"
    install -m 600 -o "$user" -g "$user" "$keyfile" "$home/.ssh/authorized_keys"
}

# Members of the sudo group get passwordless sudo; the group name differs.
sudo_group() {
    if [[ "$OS_FAMILY" == "rhel" ]]; then echo wheel; else echo sudo; fi
}

grant_sudo() {
    local group
    group="$(sudo_group)"
    printf '%%%s ALL=(ALL) NOPASSWD:ALL\n' "$group" > /etc/sudoers.d/90-admins
    chmod 440 /etc/sudoers.d/90-admins
    visudo -cf /etc/sudoers.d/90-admins || fail "sudoers drop-in is invalid"
}
