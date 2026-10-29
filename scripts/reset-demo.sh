#!/usr/bin/env bash
# Reset demo data back to the original seed.
#   ./scripts/reset-demo.sh              # whole team
#   ./scripts/reset-demo.sh tom          # one person only
#   ./scripts/reset-demo.sh --standalone # the device-B node (deletes its vault!)
set -euo pipefail
cd "$(dirname "$0")/.."

case "${1:-}" in
  "")
    docker compose down -v
    docker compose up -d
    echo "All six demo nodes were reset to the original seed." ;;
  --standalone)
    read -r -p "This deletes the standalone node's vault, keys and pairings for good. Type DELETE to continue: " a
    [ "$a" = "DELETE" ] || { echo "Cancelled."; exit 1; }
    docker compose -f docker-compose.lan.yml down -v
    echo "Standalone node removed. Start it again with scripts/start-node.sh" ;;
  priya|marcus|elena|jamal|sofia|tom)
    docker compose rm --stop --force "$1"
    docker volume rm "p2psec_$1"
    docker compose up -d "$1"
    echo "$1 was reset to the seed. Other people still remember their history with $1." ;;
  *)
    echo "Unknown option '$1'. Use: (nothing) | priya|marcus|elena|jamal|sofia|tom | --standalone"; exit 1 ;;
esac
