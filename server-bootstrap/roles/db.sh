# shellcheck shell=bash
# Role: db - PostgreSQL listening on the private network.

: "${PG_LISTEN:=localhost}"
: "${PG_ALLOW_NET:=10.0.0.0/8}"

role_packages() {
    echo "$(pkg_name postgresql)" postgresql-contrib
}

role_setup() {
    # shellcheck disable=SC2046
    pkg_install $(role_packages)

    if [[ "$OS_FAMILY" == "rhel" ]]; then
        postgresql-setup --initdb || true
    fi
    svc_enable postgresql

    configure_postgres
    systemctl restart postgresql
    fw_allow 5432
}

configure_postgres() {
    local conf hba
    conf="$(sudo -u postgres psql -tAc 'SHOW config_file')"
    hba="$(sudo -u postgres psql -tAc 'SHOW hba_file')"

    sed -i "s/^#\?listen_addresses.*/listen_addresses = '${PG_LISTEN}'/" "$conf"
    if ! grep -q "$PG_ALLOW_NET" "$hba"; then
        echo "host all all $PG_ALLOW_NET scram-sha-256" >> "$hba"
    fi
    msg "postgres listens on $PG_LISTEN, allows $PG_ALLOW_NET"
}
