#!/usr/bin/env bash
# Device A (macOS/Linux): start the six-person demo team and let other devices on the Wi-Fi pair with Tom.
#   ./scripts/start-team.sh [LAN_IP]
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/common.sh

ip="${1:-$(lan_ip)}"
set_env TOM_ADVERTISE "$ip:7606"
docker compose up -d --build
wait_healthy 8001 8002 8003 8004 8005 8006

cat <<EOF

P2PSec demo team is running. Master password for everyone: p2psec-demo
  Priya  http://127.0.0.1:8001    Marcus http://127.0.0.1:8002    Elena http://127.0.0.1:8003
  Jamal  http://127.0.0.1:8004    Sofia  http://127.0.0.1:8005    Tom   http://127.0.0.1:8006

From the other device, pair with Tom at:  $ip:7606
(If a firewall is on, allow incoming TCP 7606.)
EOF
