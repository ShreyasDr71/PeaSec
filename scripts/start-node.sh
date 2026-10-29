#!/usr/bin/env bash
# Device B (macOS/Linux): start one fresh, real (non-demo) node reachable on the Wi-Fi.
#   ./scripts/start-node.sh [LAN_IP]
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/common.sh

ip="${1:-$(lan_ip)}"
set_env LAN_IP "$ip"
docker compose -f docker-compose.lan.yml up -d --build
wait_healthy 8000

cat <<EOF

Your node is running: open http://127.0.0.1:8000 and create your vault.
Teammates pair with you at:  $ip:7600
To pair with the demo team, enter Tom's address shown on the other device (its-IP:7606).
(If a firewall is on, allow incoming TCP 7600.)
EOF
