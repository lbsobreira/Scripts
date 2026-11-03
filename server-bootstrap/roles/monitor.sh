# shellcheck shell=bash
# Role: monitor - node exporter on every role, plus Prometheus on this one.

: "${PROM_RETENTION:=30d}"

role_packages() {
    echo prometheus "$(pkg_name prometheus-node-exporter)"
}

role_setup() {
    # shellcheck disable=SC2046
    pkg_install $(role_packages)
    write_prometheus_config
    svc_enable prometheus
    fw_allow 9090
}

write_prometheus_config() {
    local targets
    # targets.txt next to bootstrap.sh: one host:port per line
    targets="$(grep -v '^#' "$SCRIPT_DIR/targets.txt" | sed 's/.*/"&"/' | paste -sd, -)"
    cat > /etc/prometheus/prometheus.yml <<EOF
global:
  scrape_interval: 30s
scrape_configs:
  - job_name: node
    static_configs:
      - targets: [${targets}]
EOF
    echo "ARGS=\"--storage.tsdb.retention.time=${PROM_RETENTION}\"" > /etc/default/prometheus
}
