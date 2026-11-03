# shellcheck shell=bash
# Role: web - nginx with a default site.

: "${SITE_NAME:=$(hostname -f)}"
: "${WEB_ROOT:=/var/www/$SITE_NAME}"

role_packages() {
    echo nginx certbot python3-certbot-nginx
}

role_setup() {
    # shellcheck disable=SC2046
    pkg_install $(role_packages)

    mkdir -p "$WEB_ROOT"
    chown -R www-data:www-data "$WEB_ROOT" 2>/dev/null || chown -R nginx:nginx "$WEB_ROOT"

    write_site
    nginx -t || fail "nginx config test failed"
    svc_enable nginx
    fw_allow 80
    fw_allow 443
}

write_site() {
    local conf=/etc/nginx/conf.d/$SITE_NAME.conf
    # Unquoted heredoc: $SITE_NAME, $WEB_ROOT and $(date) are expanded now.
    cat > "$conf" <<EOF
# Written by server-bootstrap on $(date -I)
server {
    listen 80;
    server_name $SITE_NAME;
    root $WEB_ROOT;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }

    access_log /var/log/nginx/$SITE_NAME.access.log;
}
EOF
    if [[ ! -f "$WEB_ROOT/index.html" ]]; then
        echo "<h1>$SITE_NAME</h1>" > "$WEB_ROOT/index.html"
    fi
}
