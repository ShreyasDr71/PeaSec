#!/usr/bin/env bash
# Wipe EVERYTHING on this device: your vault, keys, pairings, logs and the demo team.
# Afterwards the node starts fresh with the default sign-in user / user.
set -euo pipefail
cd "$(dirname "$0")/.."
read -r -p "This permanently deletes your vault, keys and pairings on this device. Type DELETE to continue: " a
[ "$a" = "DELETE" ] || { echo "Cancelled."; exit 1; }
docker compose down -v
docker compose up -d
echo "Done. Sign in at http://127.0.0.1:8000 as user / user."
