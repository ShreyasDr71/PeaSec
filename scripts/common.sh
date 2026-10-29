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

open_firewall() {   # $1 = this device's LAN IP. Only acts if a host firewall is actually running.
  local subnet
  subnet=$(ip -o -4 route show scope link 2>/dev/null | awk -v ip="$1" '$0 ~ ("src " ip) {print $1; exit}')
  [ -n "$subnet" ] || subnet="$1/24"
  if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet ufw 2>/dev/null; then
    echo "Firewall (ufw): allowing TCP 7600 and 7606 from $subnet (sudo may ask for your password)."
    sudo ufw allow proto tcp from "$subnet" to any port 7600,7606 >/dev/null
  elif command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet firewalld 2>/dev/null; then
    echo "Firewall (firewalld): allowing TCP 7600 and 7606 from $subnet (sudo may ask for your password)."
    for port in 7600 7606; do
      sudo firewall-cmd --permanent --add-rich-rule="rule family=ipv4 source address=$subnet port port=$port protocol=tcp accept" >/dev/null
    done
    sudo firewall-cmd --reload >/dev/null
  else
    echo "Firewall: no ufw/firewalld running, nothing to open."
  fi
}
