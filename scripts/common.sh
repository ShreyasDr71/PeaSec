# Shared helpers for the P2PSec shell scripts (macOS/Linux).

lan_ip() {
  local ip=""
  if command -v ip >/dev/null 2>&1; then
    ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<NF;i++) if ($i=="src") print $(i+1)}' | head -1)
  fi
  if [ -z "$ip" ] && command -v route >/dev/null 2>&1; then          # macOS
    local ifc; ifc=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
    [ -n "$ifc" ] && ip=$(ipconfig getifaddr "$ifc" 2>/dev/null || true)
  fi
  [ -n "$ip" ] || { echo "Could not detect this device's Wi-Fi address; pass it as the first argument." >&2; exit 1; }
  echo "$ip"
}

set_env() {   # docker compose reads .env, so a later plain "docker compose up" keeps the value
  touch .env
  grep -v "^$1=" .env > .env.tmp || true
  echo "$1=$2" >> .env.tmp
  mv .env.tmp .env
}

wait_healthy() {
  echo "Waiting for the nodes to start..."
  for port in "$@"; do
    for _ in $(seq 1 90); do
      curl -fsS "http://127.0.0.1:$port/api/status" >/dev/null 2>&1 && break
      sleep 1
    done
  done
}
