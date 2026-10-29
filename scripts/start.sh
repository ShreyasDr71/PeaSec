#!/usr/bin/env bash
# Start P2PSec on this device (macOS/Linux). Run the same script on every device on the Wi-Fi.
#   ./scripts/start.sh [LAN_IP]
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/common.sh

ip="${1:-$(lan_ip)}"
set_env LAN_IP "$ip"
docker compose up -d --build
wait_healthy 8000

cat <<EOF

P2PSec is running: http://127.0.0.1:8000
  First sign-in: username 'user', password 'user' (change both in Node settings).
  Teammates on this Wi-Fi pair with you at:  $ip:7600
  Demo mode (sign-in page) starts a seeded team; other devices can pair with its Tom at $ip:7606
  If a firewall is on, allow incoming TCP 7600 and 7606.
EOF
