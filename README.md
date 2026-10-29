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

You need Docker (Docker Desktop on Windows/macOS). The image is built from source the first time you start, or
you can pull the prebuilt one (amd64 and arm64, published by GitHub Actions on every push to `main`):

```bash
docker pull ghcr.io/shreyasdr71/peasec:latest
```

## Two devices on the same Wi-Fi

**Device A: the demo team.** Six people from the fictional P2PSec IT team, already paired, with history.

```powershell
# Windows (run PowerShell as administrator so the script can open the firewall port)
powershell -ExecutionPolicy Bypass -File scripts\start-team.ps1
```
```bash
# macOS / Linux
./scripts/start-team.sh
```

The script finds this device's Wi-Fi address, opens TCP 7606 in the Windows firewall, starts the six nodes, and
prints the address the other device should pair with (for example `192.168.1.10:7606`, which is Tom's node).

**Device B: your own node.** A fresh, real node with keys generated on that device.

```powershell
powershell -ExecutionPolicy Bypass -File scripts\start-node.ps1    # Windows, as administrator
```
```bash
./scripts/start-node.sh                                               # macOS / Linux
```

Open http://127.0.0.1:8000 on device B, create your vault, go to **Pair a device** and enter the address device A
printed. On device A, open Tom (http://127.0.0.1:8006), accept the request, and read the six-digit codes to each
other. Device B warns that Tom uses demo keys (true: anyone with the demo seed could impersonate Tom); tick the box
to continue. Then, from device B, ask Tom for his sandbox VM login, or create a group and add Tom.

If the script cannot find the right network, pass the address yourself: `-LanIp 192.168.1.20` (PowerShell) or
`./scripts/start-node.sh 192.168.1.20`. If pairing times out, the firewall on the receiving device is the usual
cause: allow inbound TCP 7606 on device A and 7600 on device B. Broadcast discovery does not cross Docker Desktop,
so between devices you always type the address.

## The demo team

Every demo node's master password is `p2psec-demo`. Open each person in a separate private browser window (cookies
are per host and port).

| Person | Role | UI |
|---|---|---|
| Priya Nair | IT Operations Lead. Custodian: Infrastructure | http://127.0.0.1:8001 |
| Marcus Chen | DBA. Custodian: Databases | http://127.0.0.1:8002 |
| Elena Rossi | Security Engineer. Custodian: Security Tools, Infrastructure | http://127.0.0.1:8003 |
| Jamal Okafor | Backend Developer. Member: Databases, Infrastructure | http://127.0.0.1:8004 |
| Sofia Alvarez | Finance Systems Analyst. Custodian: Finance Apps | http://127.0.0.1:8005 |
| Tom Becker | Intern. Paired with nobody | http://127.0.0.1:8006 |

Things to try:

1. **Priya:** *Waiting for me* has Marcus's 8-hour request for the Backup server. It is over the group's 4-hour
   limit, so it needs her approval. Approve it with a shorter time.
2. **Elena:** *Who has access* shows that checkout too, because co-custodians share activity. Revoke it, then watch
   Marcus's copy disappear and a rotation task appear for Priya and Elena.
3. **Jamal:** he already holds Prod PostgreSQL with a live countdown. Request *Redis cluster*: it is approved
   automatically. Ask Elena for *SIEM admin*: it is denied, because Security Tools is members-only.
4. **Sofia:** Jamal asked for her personal Expense tool login. Approve it and pick which credential to share.
5. **Priya:** *Rotation tasks* has AWS root (Marcus's checkout expired yesterday). Rotate it; Elena gets the new secret.
6. **Tom → Sofia:** on *Pair a device*, pair Tom with `sofia:7600`. Accept on Sofia's screen and compare the codes.
7. **Audit:** *Event log* and *Log integrity* on any node.

Only one device should run the demo team: every copy derives the same six identities from the same public seed.

## Reset the seeded values

The seed is rebuilt whenever a node starts with an empty data volume, with timestamps relative to that moment (so
Jamal's checkout again has about 45 minutes left).

| What | Windows | macOS / Linux | Plain Docker |
|---|---|---|---|
| Whole demo team | `scripts\reset-demo.ps1` | `./scripts/reset-demo.sh` | `docker compose down -v` then `docker compose up -d` |
| One person (e.g. Tom) | `scripts\reset-demo.ps1 -Node tom` | `./scripts/reset-demo.sh tom` | `docker compose rm -sf tom`, `docker volume rm p2psec_tom`, `docker compose up -d tom` |
| Device B's own node | `scripts\reset-demo.ps1 -Standalone` | `./scripts/reset-demo.sh --standalone` | `docker compose -f docker-compose.lan.yml down -v` |

Run the `.ps1` scripts with `powershell -ExecutionPolicy Bypass -File ...`. Resetting one person leaves the others'
memory of them intact, so after resetting Tom, re-pair device B with him. Resetting device B's node deletes its
vault and keys for good: it asks you to type `DELETE` first.

Stop without deleting anything: `docker compose stop` (and `docker compose -f docker-compose.lan.yml stop` on B).

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

**Demo keys are public.** `DEMO_SEED` derives every demo identity, and the node refuses to start with it unless
`DEMO_MODE=1`. Never put real secrets in a demo node.

## Development

```bash
cd backend && python -m venv .venv && .venv/Scripts/pip install -r requirements-dev.txt   # .venv/bin on macOS/Linux
.venv/Scripts/python -m pytest          # 91 tests: crypto, vault, audit, pairing (incl. MITM), channel, groups, engine, peers, API

cd frontend && npm ci && npm run dev    # UI on :5173, proxies /api to a node on 127.0.0.1:18001
```

Run a node outside Docker: `NODE_ID=priya DEMO_MODE=1 DEMO_SEED=dev UI_PORT=18001 python -m p2psec` from `backend/`.

```
backend/p2psec/
  crypto.py     primitives (cryptography lib only)     pairing.py   commit-reveal + SAS
  vault.py      Argon2id, two key tiers                channel.py   Noise_KK sessions, replay guard
  audit.py      hash-chained signed log, anchors       peer.py      TCP service, outbox, pairing sessions
  groups.py     signed group documents                 engine.py    requests, checkouts, receipts, rotation, sync
  api.py        local REST API + static UI             seed.py      the demo team
frontend/src/   React UI (pages/, components/Logo.jsx is the pea mark)
docs/superpowers/specs/  design     docs/superpowers/plans/  implementation plan
```
