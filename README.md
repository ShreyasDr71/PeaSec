# P2PSec (PeaSec)

Peer-to-peer privileged access management for IT teams on a LAN.

**This is not a centralized system.** Every person runs their own P2PSec node on their own computer. There is no server,
no directory and no sync service. Secrets live only on the machines of the people who own them (personal credentials) or
who are custodians of them (group credentials). Nodes talk directly to each other over the local network.

- **Pairing with a six-digit code.** Two people pair once; both screens show the same code, and they confirm it out loud.
  The commit-then-reveal exchange behind it gives a man in the middle one 1-in-a-million guess, not a way to force a match.
- **Encrypted, authenticated sessions.** After pairing, every connection is a Noise_KK handshake against the pinned keys
  (X25519, ChaCha20-Poly1305, SHA-256), with forward secrecy and replay protection.
- **Checkouts, not copies.** You request a credential with a ticket number and a reason. Group members are approved
  automatically within policy; Critical accounts always need a custodian. A checkout has a timer, and when it ends the
  secret is deleted from the holder's machine and a rotation task is raised for the owner.
- **Groups held by custodians.** A group's credentials are held by 1–3 custodians, whose nodes share the group's
  activity so each sees every checkout. Group definitions are signed, hash-linked documents; changing custodians needs
  a majority of them.
- **Tamper-evident audit.** Every node keeps a hash-chained, signed log. Peers remember how far each other's logs have
  reached, so a rewritten or truncated log is flagged by the people who saw it. Every share produces signed receipts.
- **Encrypted at rest.** The master password unlocks (Argon2id) two keys. Locking the UI wipes the personal key; the
  node keeps serving group checkouts. "Lock and go offline" wipes everything.

## Get it

```bash
git clone https://github.com/ShreyasDr71/PeaSec.git
cd PeaSec
```

You need Docker (Docker Desktop on Windows/macOS). The image is built from source the first time you start, or you can
pull the prebuilt one (amd64 and arm64, published by GitHub Actions on every push to `main`) and skip the build:

```bash
docker pull ghcr.io/shreyasdr71/peasec:latest
```

## Start it (same steps on every device)

```powershell
# Windows (the first run asks once for permission to open the firewall)
powershell -ExecutionPolicy Bypass -File scripts\start.ps1
```
```bash
# macOS / Linux
./scripts/start.sh
```

The script finds this device's Wi-Fi address and opens TCP 7600 and 7606 to devices on your local network only.
On Windows that is one "Allow changes?" prompt, and it works even when Windows has marked the Wi-Fi as Public; on Linux
it uses `ufw`/`firewalld` with `sudo` if one is running. Then it starts the container and prints what to do next. A
container cannot change its host's firewall, so this step lives in the script, not in Docker. By hand it is `LAN_IP=<this device's Wi-Fi address> docker compose up -d`.

Open **http://127.0.0.1:8000** and sign in as **`user` / `user`**. A fresh node is just you: no teammates, no
credentials, no history. A red banner reminds you to change the username and master password in *Node settings*
until you do.

## Use it between two devices on the same Wi-Fi

1. Run the start script on both devices and sign in on each.
2. On one device, go to *Pair a device* and enter the other device's address, which the script printed, such as
   `192.168.1.20:7600`.
3. Accept the request on the other device and read the six-digit codes to each other. Confirm only if they match.
4. Add a credential on one device. From the other, *Request a credential → From a person*, then approve it.

If the script picks the wrong network, pass the address: `-LanIp 192.168.1.20` (PowerShell) or
`./scripts/start.sh 192.168.1.20`. If pairing says it *could not reach* the other computer: make sure that computer was
started with the start script (and you clicked Yes on Windows), then test with `nc -zv <ip> 7600` (Linux/macOS) or
`Test-NetConnection <ip> -Port 7600` (Windows). If that fails with both firewalls open, the router is isolating Wi-Fi
clients; turn that off or use a phone hotspot. Broadcast discovery does not cross Docker Desktop, so you type addresses.

## Demo mode (optional)

Nothing is seeded unless you ask for it. Click **Demo mode** on the sign-in page (or in *Settings* when signed in),
then **Start demo mode**. Six fictional people from an IT team start inside the same container, already paired, with
groups, requests, checkouts and audit history. Each opens in its own tab at `http://127.0.0.1:8000/demo/<name>/` and
signs in with their own name and the password `p2psec-demo`.

| Person | Role | Sign in |
|---|---|---|
| Priya Nair | IT Operations Lead. Custodian: Infrastructure | `priya` |
| Marcus Chen | DBA. Custodian: Databases | `marcus` |
| Elena Rossi | Security Engineer. Custodian: Security Tools, Infrastructure | `elena` |
| Jamal Okafor | Backend Developer. Member: Databases, Infrastructure | `jamal` |
| Sofia Alvarez | Finance Systems Analyst. Custodian: Finance Apps | `sofia` |
| Tom Becker | Intern. Paired with nobody | `tom` |

Things to try:

1. **Priya:** *Waiting for me* has Marcus's 8-hour request for the Backup server. It is over the group's 4-hour
   limit, so it needs her approval. Approve it with a shorter time.
2. **Elena:** *Who has access* shows that checkout too, because co-custodians share activity. Revoke it, then watch
   Marcus's copy disappear and a rotation task appear for Priya and Elena.
3. **Jamal:** he already holds Prod PostgreSQL with a live countdown. Request *Redis cluster*: it is approved
   automatically. Ask Elena for *SIEM admin*: it is denied, because Security Tools is members-only.
4. **Sofia:** Jamal asked for her personal Expense tool login. Approve it and pick which credential to share.
5. **Priya:** *Rotation tasks* has AWS root (Marcus's checkout expired yesterday). Rotate it; Elena gets the new secret.
6. **Pairing:** Tom is paired with nobody. Pair him with your own node (*Pair a device*, address `127.0.0.1:7606`)
   or with a node on another device (`<this device's Wi-Fi address>:7606`). The real node warns that Tom uses demo
   keys, which is true: anyone with the public demo seed could impersonate him.

Demo users' keys come from a public seed: never put real secrets in them. Your own node is never touched by demo mode.
Demo mode stays on across restarts until you press *Stop demo mode*.

## Reset

| What | How |
|---|---|
| Demo team back to its original seed | *Demo mode → Reset demo data*, or `scripts\reset-demo.ps1` / `./scripts/reset-demo.sh` |
| Turn demo mode off | *Demo mode → Stop demo mode* (starting again keeps the demo data) |
| Everything on this device (your vault, keys, pairings, and the demo) | `scripts\reset-all.ps1` / `./scripts/reset-all.sh`, or `docker compose down -v` then `docker compose up -d`. You are back to `user` / `user`. |
| Stop without deleting anything | `docker compose stop` |

The seed's timestamps are relative to the moment the demo is (re)built, so after a reset Jamal's checkout again has
about 45 minutes left. Run the `.ps1` scripts with `powershell -ExecutionPolicy Bypass -File ...`. `reset-all` asks
you to type `DELETE` first, because it destroys your real vault.

## Security notes

| Threat | Mitigation |
|---|---|
| Eavesdropping on Wi-Fi/LAN | Every byte between nodes is inside Noise (ChaCha20-Poly1305) |
| Man in the middle at pairing | Commit-then-reveal key exchange + human-compared six-digit code |
| Man in the middle later | Noise_KK against the keys pinned at pairing; unknown keys are refused and logged |
| Replay | Noise nonces, per-message ids remembered for 24 h, 5-minute clock window |
| A paired peer lying about who it is | Identity always comes from the authenticated channel, never from message fields |
| Stolen laptop (powered off) | Argon2id-wrapped keys. Credential names are visible; secrets are not |
| Log tampering, even by the node's owner | Hash chain + signatures + peers' anchors of your log head |
| A removed custodian taking a group back | Versions must extend the chain you hold; forks are refused and alerted |
| A holder keeping a copy after checkout | Not preventable. Checkouts end with deletion, receipts and a rotation task |
| A malicious web page talking to your node | UI bound to 127.0.0.1, Host allow-list, SameSite=Strict cookie, CSRF header |

Not in scope: a compromised machine while it is unlocked, Bluetooth (Docker cannot reach the radio; the transport is
abstracted so a native Bluetooth transport can be added), internet/WAN use.

**Demo keys are public.** Every demo identity derives from a public seed and only exists after you press *Demo
mode*. Never put real secrets in a demo user.

## Development

```bash
cd backend && python -m venv .venv && .venv/Scripts/pip install -r requirements-dev.txt   # .venv/bin on macOS/Linux
.venv/Scripts/python -m pytest          # 116 tests: crypto, vault, audit, pairing (incl. MITM), channel, groups, engine, peers, API

cd frontend && npm ci && npm run dev    # UI on :5173, proxies /api to a node on 127.0.0.1:18001
```

Run a node outside Docker: `UI_PORT=18001 DATA_DIR=./data python -m p2psec` from `backend/` (signs in as user / user).

```
backend/p2psec/
  crypto.py     primitives (cryptography lib only)     pairing.py   commit-reveal + SAS
  vault.py      Argon2id, two key tiers                channel.py   Noise_KK sessions, replay guard
  audit.py      hash-chained signed log, anchors       peer.py      TCP service, outbox, pairing sessions
  groups.py     signed group documents                 engine.py    requests, checkouts, receipts, rotation, sync
  api.py        local REST API + static UI             seed.py      the demo team's data
  demo.py       opt-in in-process demo team            node.py      one node: vault, peer service, loops
frontend/src/   React UI (pages/, components/Logo.jsx is the pea mark)
docs/superpowers/specs/  design     docs/superpowers/plans/  implementation plan
```
