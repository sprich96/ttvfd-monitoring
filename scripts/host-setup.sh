#!/usr/bin/env bash
# One-time host prep for the monitoring VM. Run with sudo from the repo root.
# Idempotent.
set -euo pipefail
ROOT="${DATA_ROOT:-/srv/monitoring}"

install -d -m 0755 "$ROOT"
install -d -o 65534 -g 65534 -m 0750 "$ROOT/prometheus" "$ROOT/alertmanager"
install -d -o 472   -g 0     -m 0750 "$ROOT/grafana"
install -d -o 10001 -g 10001 -m 0750 "$ROOT/loki"
install -d -o 0     -g 0     -m 0750 "$ROOT/alloy" "$ROOT/caddy" "$ROOT/caddy/data" "$ROOT/caddy/config"

# Let Prometheus (on br-mon) reach the host node_exporter bound to 172.30.0.1:9100.
# Docker-published ports (80/443) bypass ufw already.
if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then
  ufw allow in on br-mon to 172.30.0.1 port 9100 proto tcp comment 'prometheus->node_exporter'
fi
echo "done: $ROOT"
