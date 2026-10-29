# P2PSec — Decentralized LAN Password Sharing for Teams

*Design doc · 2026-10-29*

## 1. Intent

A password manager for a medium-sized team (roughly 10–50 people) where **there is no central server**. Every person runs their own P2PSec node on their own computer. Secrets live only on the machines of the people who own or are custodians of them. When people are on the same LAN, their nodes talk directly, peer to peer, over channels that an active man-in-the-middle cannot read or tamper with.

People can:
- keep their own credentials in a local encrypted vault,
- **request** a credential from a teammate, who approves or denies it,
- get **time-limited** access (a lease) that self-destructs on the recipient's machine when the timer ends,
- belong to **groups** whose shared credentials are held by a few **custodians** and handed to members on request, auto-approved by group policy,
- see a tamper-evident **audit trail** of who held which credential and when.

The UI should feel like ServiceNow: an application navigator on the left, list views with filters, record forms with related lists, and request/approval queues.

> **This is not a centralized system.** No node is special. There is no directory server, sync server, or coordinator. Team structure (groups, custodians) is expressed as signed documents that travel between peers. If every custodian of a group is offline, that group's credentials are unavailable. That is the trade-off of approach B (§4).

**Audience (user-stated): IT staff using it for privileged access security management (PASM).** Shared credentials are privileged accounts: domain admins, root, service accounts, network devices, cloud break-glass. That means the language and fields follow PAM conventions:
- A lease is a **checkout**, and its end is a **check-in**.
- A request requires a **ticket reference** (INC/CHG/RITM number) plus a justification.
- Credentials carry an **account type** (Domain Admin, Local Admin, Root, Service Account, Network Device, Cloud Root, Database, Application) and a **criticality** (Critical/High/Medium/Low).
- **Critical** accounts are never auto-approved, even for group members. They always need a custodian to approve by hand.
- **Rotate-on-check-in** is the default for Critical and High accounts. Their rotation task is raised at check-in, not just at expiry.

## 2. Goals, non-goals, anti-goals

**Goals**
- Pairing between two nodes that defeats MITM through a human-verified short authentication string (SAS).
- All peer traffic is encrypted and mutually authenticated with keys pinned at pairing, and has forward secrecy.
- Secrets are encrypted at rest under a key derived from the user's master password.
- Request → approve/deny → lease with expiry → auto-delete → receipt.
- Group-shared credentials held by custodians (approach B), with auto-approval for group members within policy limits.
- An audit log on every node: append-only, hash-chained and signed. Both sides of every share keep signed receipts.
- A rotation reminder whenever a lease ends or is revoked ("Y had this password; rotate it").
- Runs in Docker. One compose file brings up a seeded demo team on one machine, and the same image runs on a second computer to pair across machines.

**Non-goals (this version)**
- **Bluetooth.** Docker on Windows/macOS can't reach the Bluetooth radio. The transport layer is abstracted (§6.1) so a native Bluetooth transport can be added later.
- Internet / WAN operation, NAT traversal, relays.
- Transitive trust ("I trust whoever Priya vouches for"). Every channel requires a direct pairing.
- Mobile apps, browser autofill extensions.
- Protecting against a compromised machine while it is unlocked.
- Preventing a recipient from memorizing or copying a password they were given. The system cannot do this; it mitigates with leases, logs and rotation reminders.

**Anti-goals (a failure even if it "works")**
- Any component that every node depends on: a hidden central server.
- A secret crossing the network unencrypted, or sitting on disk unencrypted.
- Pairing that completes without both humans confirming the SAS.
- Logs that can be edited or truncated without detection.
- Cipher negotiation or downgrade paths. One fixed protocol suite with a version number.
- Home-grown cryptographic primitives. Use vetted libraries and compose standard constructions only.

## 3. Constraints

- Runs as a Docker image (Linux container). Must work under Docker Desktop on Windows.
- Docker Desktop NATs containers, so LAN broadcast discovery does not cross machines. Cross-machine connections use a manually entered `host:port`. Within one compose network, discovery works.
- The demo uses seed data and must be resettable.

## 4. Approaches considered (group sharing)

| | Approach | Trade-off | Decision |
|---|---|---|---|
| A | Every group member holds a replicated copy of group secrets | Works offline, no waiting; but every laptop is an exposure point, removal requires rotating everything, logs lose meaning since members never request | Rejected |
| **B** | **1–3 custodians per group hold the secrets; members request and are auto-approved by group policy; leases expire** | Fewer copies, every access logged, timers and revocation are meaningful, matches the ServiceNow request/approve model; needs ≥1 custodian online | **Chosen by user** |
| C | Threshold secret sharing across members | Very strong, but far too complex for the value here | Dropped |

Already agreed with the user: SAS pairing to stop MITM; on lease expiry, deletion plus a rotation reminder (an honest model, not fake revocation).

## 5. Architecture

```
┌──────────────── Person's computer ────────────────┐
│  Browser ──HTTP(127.0.0.1:8000)──►  P2PSec node   │
│                                     ├─ Web UI (React, served by node)
│                                     ├─ Local API (FastAPI)
│                                     ├─ Vault (SQLite + encrypted fields)
│                                     ├─ Audit log (hash chain, signed)
│                                     ├─ Policy engine (groups, leases, timers)
│                                     └─ Peer service (TCP :7600) ◄──► other nodes
└───────────────────────────────────────────────────┘
```

**Stack (my call):** Python 3.12, FastAPI, `cryptography` (X25519, Ed25519, ChaCha20-Poly1305, HKDF, SHA-256), `argon2-cffi`, SQLite. React + Vite for the UI, built into the image as static files. Single process per node, asyncio. The peer service is a raw TCP asyncio server, not HTTP, which keeps the attack surface small.

**Local UI security:** the UI/API port is meant to be reachable only from the person's own machine. Compose maps it as `127.0.0.1:<port>:8000`. The API requires a session cookie obtained by unlocking with the master password (HttpOnly, SameSite=Strict), a CSRF token header on mutating calls, and an idle auto-lock (default 10 min) that wipes the in-memory vault key.

## 6. Security design

### 6.1 Identity and transport
- Each node generates on first run an **Ed25519 identity key** (signing) and an **X25519 static key** (key agreement). Fingerprint = first 128 bits of SHA-256 over both public keys, shown as hex groups.
- Transport interface: `connect(address) -> byte stream`. The only implementation for now is TCP. Bluetooth RFCOMM can implement the same interface later.
- Framing: 4-byte big-endian length prefix, max frame 1 MiB.

### 6.2 Pairing (MITM-resistant, commit-reveal + SAS)
A naive "exchange keys, show 6 digits" lets a MITM grind its own ephemeral key until both sides' SAS match. To prevent that, use **commit-before-reveal** (the same idea as ZRTP and Bluetooth numeric comparison):

1. Initiator A generates ephemeral `eA` and nonce `nA`, and sends `commit = SHA-256(eA_pub ‖ nA ‖ IDA_pub)`.
2. Responder B generates `eB`, `nB`, and sends `eB_pub, nB, IDB_pub` in clear.
3. A reveals `eA_pub, nA, IDA_pub`. B checks it against `commit` and aborts on mismatch.
4. Both compute `k = HKDF(X25519(eA, eB), salt = transcript_hash)` over the full transcript.
5. **SAS** = 6 decimal digits from `HKDF(k, info="p2psec-sas")`, shown on both screens along with the peer's claimed name and fingerprint.
6. Under `k` (ChaCha20-Poly1305), both exchange a signed identity card: name, role, Ed25519 pub, X25519 static pub, and a signature over the transcript hash with their Ed25519 key. This proves possession of the identity key.
7. Each human confirms "codes match" in the UI. Pairing completes only when **both** confirm. Each side's confirmation is sent under `k`. Either side rejecting, or a 120-second timeout, aborts everything.
8. On success, each node **pins** the peer's keys in its contacts table and writes a `PAIRED` audit event.

Because A commits before seeing anything and B reveals before A does, a MITM gets exactly one guess per pairing attempt: a 1-in-10⁶ chance, and each attempt needs humans to confirm. The UI must say plainly "Confirm only if the other person reads you the same code, in person or by phone."

Pairing is initiated by entering the peer's `host:port`, or by picking from discovered peers (§6.6). The responder sees an incoming pairing request in the UI and must accept it before step 2. No auto-accept.

### 6.3 Session channel (after pairing)
- **Noise_KK_25519_ChaChaPoly_SHA256**: both sides already know each other's static X25519 keys from pairing. Use the `noiseprotocol` Python package. Fallback if that package is a problem: an equivalent SIGMA-style handshake (ephemeral X25519 signed by Ed25519 identity, HKDF over the transcript), with the replacement noted in code.
- This gives mutual authentication against pinned keys, forward secrecy (ephemeral keys), and an AEAD on every message with Noise's counter nonces, which rejects replay and reordering within a session.
- A fresh handshake per connection. Connections are short-lived, one request/response exchange or a small batch.
- Unknown or unpinned static key → handshake fails → logged as `AUTH_FAILURE` with the source address.
- **Identity comes from the channel, never the payload.** The sender of every message (requester, approver, receipt or revoke sender, group-document pusher) is the peer whose pinned key completed the Noise handshake. Any `*_fpr` field in a JSON body that disagrees with the channel identity → reject and log `AUTH_FAILURE`.
- Application messages inside the channel are JSON, each with `msg_id` (UUID), `ts`, and `type`. Receivers keep a 24 h cache of seen `msg_id`s and reject duplicates, which covers cross-session replay. They also reject `ts` skew over 5 minutes.

### 6.4 Vault at rest
- On first run, the user sets a master password. `KEK = Argon2id(password, salt, t=3, m=64 MiB, p=2)`.
- A random 256-bit **vault key** is generated and stored wrapped by the KEK (ChaCha20-Poly1305).
- Secret fields (password, notes, TOTP seed), private keys and lease contents are each encrypted under the vault key with a random nonce and `AAD = record_type ‖ record_id`. Metadata (credential names, URLs, usernames, group names, log entries) stays plaintext in SQLite so lists and filters work while locked-but-logged-in views stay quick. Documented trade-off: a stolen disk reveals *which* credentials exist, not their values.
- **Two key tiers (decided by user: locked nodes stay online).** Two random 256-bit keys are each wrapped by the KEK:
  - **Personal key:** encrypts the user's personal credential secrets and the secrets of leases they've received.
  - **Service key:** encrypts the Ed25519 and X25519 private keys and the group secrets this node is custodian for.
- **Boot:** the node needs one unlock with the master password after each start. Until then it is offline to peers.
- **Lock (idle auto-lock or the Lock button):** wipes the personal key and the UI session only. The service key stays in memory, so the node keeps doing its network work:
  - Noise handshakes.
  - Signing log entries and receipts.
  - Enforcing lease expiry.
  - Auto-approving group requests within policy.
  - Accepting incoming requests that need a human, and queuing them until the owner unlocks.
- **Full lock** (user menu → "Lock & go offline", or process exit) wipes both keys, and the node goes offline to peers until the next unlock.
- Received leases still expire on time while locked. Deletion needs no key; it removes the ciphertext row.
- Changing the master password re-wraps both keys only.

### 6.5 Audit log
- Append-only table. Each entry: `seq, ts, actor_fpr, event_type, subject (credential/group/peer ids), details (JSON), prev_hash, hash, sig`. `hash = SHA-256(canonical_json(entry without hash/sig) ‖ prev_hash)`, and `sig` = the node's Ed25519 signature over `hash`.
- **Receipts:** for every share event (lease granted, lease expired, revoked, viewed), the two nodes exchange signed event records. Each node stores the counterpart's signed record alongside its own. The owner can prove the recipient acknowledged receipt, and vice versa.
- **Verify chain** action in the UI recomputes hashes and checks signatures, highlighting the first break.
- **Anchoring against the node's own owner.** A node signs its own chain, so on its own the chain can't stop its owner from rewriting or truncating it. To make that detectable, every receipt and every session carries the sender's current `(seq, head_hash)`, signed. Each node stores the latest anchor it has seen from each peer. If a peer later presents a lower `seq`, or a different hash for an anchored `seq` (checked when a peer shares its log for a "Who Has Access" query), the node raises a `LOG_ANCHOR_MISMATCH` alert naming that peer. The owner is therefore in the threat model for log tampering: they can't silently rewrite history that anyone else has anchored.
- Event types (minimum): `VAULT_CREATED, UNLOCKED, LOCKED, UNLOCK_FAILED, CRED_CREATED, CRED_UPDATED, CRED_DELETED, CRED_VIEWED, CRED_COPIED, PAIR_STARTED, PAIRED, PAIR_REJECTED, UNPAIRED, AUTH_FAILURE, REQUEST_SENT, REQUEST_RECEIVED, REQUEST_APPROVED, REQUEST_AUTO_APPROVED, REQUEST_DENIED, LEASE_GRANTED, LEASE_RECEIVED, LEASE_VIEWED, LEASE_EXPIRED, LEASE_REVOKED, ROTATION_DUE, ROTATION_DONE, GROUP_CREATED, GROUP_UPDATED, GROUP_SYNCED`.

### 6.6 Discovery
- Optional UDP broadcast beacon on port 7601 every 15 s: `{name, fingerprint, peer_port}`. Beacons are **untrusted hints only**. They're used to fill the "discovered nearby" list and to update a known contact's last-seen address. Authenticity comes from the Noise handshake, never from the beacon.
- Within a compose network this works. Across machines under Docker Desktop it does not, so the UI always offers manual `host:port` entry.
- `ADVERTISE_ADDR` env var lets a container advertise the host's LAN IP and port instead of its internal IP.

### 6.7 Threat model summary
| Threat | Mitigation |
|---|---|
| Passive eavesdropper on LAN/Wi-Fi | Noise AEAD encryption |
| Active MITM at pairing | Commit-reveal + human-verified SAS |
| Active MITM after pairing | Pinned static keys in Noise_KK |
| Replay / reordering | Noise nonces, msg_id cache, timestamp window |
| Stolen laptop, node powered off / fully locked | Argon2id-wrapped keys; metadata visible |
| Memory read on a soft-locked node | Out of scope (service key is resident by design); personal secrets are not resident |
| Log tampering | Hash chain + signatures + counterpart receipts |
| Recipient keeps a copy after lease | Not preventable → rotation reminder + audit trail |
| Spoofed discovery beacon | Beacons untrusted; handshake authenticates |
| Malicious local web page hitting UI | Localhost bind, session cookie, SameSite=Strict, CSRF header, Host header check |

## 7. Team model (decentralized)

### 7.1 People and contacts
Each node has one owner (a person) with `name, title, department`. A node's **contacts** are the peers it has paired with. There is no team directory; "the team" is the union of everyone's pairings.

**Required pairings for approach B:** each member pairs with their groups' custodians, and custodians of the same group pair with each other. For a 30-person team with ~4 groups, that's roughly members × custodians, not everyone-with-everyone.

### 7.2 Groups
A group is a **signed group document**:
```
{ group_id, name, description, version,
  custodians: [ {fpr, name} ],    # 1–3
  members:    [ {fpr, name} ],
  policy: { auto_approve_members: true, max_lease_minutes: 240,
            default_lease_minutes: 60, allow_non_member_requests: true },
  credentials: [ {cred_id, name, url, username} ],   # metadata only
  signed_by: fpr, sig }
```
- **Version chain.** Every version carries `prev_hash` (the SHA-256 of the canonical previous version), and nodes keep the full version history. A node accepts a new version only if it **extends the head it already holds**. A push sends every missing version since the recipient's head, and each one is validated in order.
- **Who can sign what:**
  - Credential list, policy, name/description, and member changes need any single custodian of the previous version.
  - **Custodian list changes** need signatures from a **majority of the previous version's custodians**: 1 of 1, 2 of 2, 2 of 3. So one custodian can't remove the others or quietly add an accomplice.
- **Forks:** if a node sees two different versions that both claim the same parent, it keeps its current head, refuses the other, and raises a `GROUP_FORK` alert on that group, naming both signers, for custodians to resolve. There is no automatic "highest number wins". That rule is what would let a removed custodian take the group back by publishing their own higher-numbered branch.
- **Genesis (v1):** a node accepts a new `group_id` only if v1 was pushed over the channel by the custodian who signed it, that signer is a paired contact, and the receiving node appears in v1 as a member or custodian. Accepting it is logged as `GROUP_CREATED (received)`.
- The document is pushed to every paired member and custodian when it changes, and pulled on reconnect. Members see the group's credential list (metadata only) and can request any of them.
- **Group secrets** exist only on custodian nodes. When a custodian adds or rotates a group credential, it pushes the encrypted value to the other custodians over their channel (custodian sync). Custodian sync is the only place secrets replicate beyond a lease.
- **Custodian sync also carries group activity:** requests, approval and denial decisions, leases (metadata only, never the leased secret), revocations, receipts, and rotation tasks for that group's credentials. These are immutable event records keyed by UUID, so merging is a plain union with no conflicts. Derived state ("active leases", "rotation due") is computed from the merged events. Consequences:
  - Every custodian sees every lease.
  - Any custodian can revoke a lease that another custodian granted.
  - A rotation task is cleared when any custodian records `ROTATION_DONE`.
  - Before approving, a custodian checks the merged events. If the requester already holds an active lease on that credential, the custodian extends that lease rather than issuing a second one.
- Removing a member: bump the version without them, and the node raises `ROTATION_DUE` for every group credential they held an active or past lease on within the last N days (configurable, default 30).

### 7.3 Requests and leases
- **Request:** `{request_id, requester_fpr, target: (owner_fpr | group_id), cred_id or free-text "what I need", reason, requested_minutes}`.
  - Personal credential → sent to the owner's node.
  - Group credential → sent to the first reachable custodian. The UI shows which custodians are online.
- **Approval:**
  - Group member + `auto_approve_members` + `requested_minutes ≤ max_lease_minutes` → custodian node auto-approves (`REQUEST_AUTO_APPROVED`). The custodian human still sees it in their activity feed.
  - Otherwise it goes into the approver's **Approvals** queue. The approver can approve (and adjust the duration down), deny with a comment, or let it sit. Pending requests expire after 24 h.
  - If the target is offline, the requester node queues the request and retries on reconnect. The UI shows "Waiting for peer".
- **Lease:** on approval, the approver node sends `{lease_id, cred_id, secret, expires_at}` over the channel. The recipient stores it encrypted under its vault key. The recipient's node **enforces expiry locally** (a timer sweep every 15 s plus a check on access) and deletes the secret at `expires_at`, then sends a signed `LEASE_EXPIRED` receipt.
- **Revoke early:** the approver clicks Revoke and a `LEASE_REVOKED` message goes out (queued if the peer is offline). The recipient deletes immediately and sends a receipt. Local expiry still applies regardless of revoke delivery.
- **Rotation reminder:** when any lease on a credential ends (expired or revoked), the owner/custodian sees a `Rotation due` task on that credential. It's cleared by updating the secret (`ROTATION_DONE`) or by dismissing it with a reason (logged).
- **Viewing:** revealing or copying a leased secret logs `LEASE_VIEWED` locally and sends a viewed receipt to the grantor.
- Clock note: expiry uses the recipient's clock. A ±5 min skew is tolerated (§6.3). This is acceptable for a demo; noted as a limitation.

## 8. UI (ServiceNow-like)

Layout: a dark top banner (product name, global search, lock button, user menu), a left **application navigator** with a filter box, and a main content pane. List views have column headers, a filter breadcrumb, sorting and pagination. Records open as forms with field sections and **related lists** at the bottom (tabs). State badges: Pending / Approved / Denied / Active / Expired / Revoked.

Navigator modules:
- **Self-Service:** Dashboard; Request a Credential (catalog-style form); My Requests
- **Vault:** My Credentials; Shared with Me (active leases with countdown)
- **Approvals:** Pending My Approval; Approval History
- **Groups:** My Groups; Group record (members, custodians, policy, credentials related lists)
- **Peers:** Paired Devices; Pair New Device (shows the SAS flow); Nearby (discovery)
- **Audit:** Event Log (filterable); Who Has Access (per credential: current lease holders + history); Verify Log Integrity
- **Settings:** profile, auto-lock, rotation window, change master password

**Branding:** the product is called **P2PSec** (a pun on "pea"). The logo is a hand-built, highly detailed **SVG pea pod**: an open pod drawn as black-and-white line art with fine engraving-style hatching, veins and a curled tendril, and the peas inside rendered in **green**, the only color. It appears in the top banner (small, on the dark banner the line art inverts to white), on the unlock and pairing screens (large), and as the favicon (a simplified single pea). The UI accent color is derived from the pea green.

Dashboard tiles: pending approvals, my open requests, active leases (out and in), leases expiring within 1 h, rotations due, peers online.

Credential form related lists: *Access History* (leases), *Requests*, *Audit Events*, *Rotation Tasks*.

Lease countdowns update live. The UI polls the local API every 5 s, or uses an SSE stream (builder's choice).

## 9. Seed data (demo team: the "P2PSec" team, fictional)

Six nodes in compose. **Demo master password for every seeded node: `p2psec-demo`** (shown on the unlock screen only when `DEMO_MODE=1`).

| Node | Person | Title | Custodian of | Member of |
|---|---|---|---|---|
| priya | Priya Nair | IT Operations Lead | Infrastructure | Security Tools |
| marcus | Marcus Chen | Database Administrator | Databases | Infrastructure |
| elena | Elena Rossi | Security Engineer | Security Tools, Infrastructure | — |
| jamal | Jamal Okafor | Backend Developer | — | Databases, Infrastructure |
| sofia | Sofia Alvarez | Finance Systems Analyst | Finance Apps | — |
| tom | Tom Becker | Engineering Intern | — | — (unpaired, used to demo pairing) |

**Groups and credentials** (metadata below; secrets are generated random strings):
- **Infrastructure** (custodians Priya, Elena; members Marcus, Jamal; policy max 240 min, default 60): AWS root account (`aws-root@p2psec.example`), vCenter admin (`administrator@vsphere.local`), Core switch SSH (`netadmin`), Backup server (`veeam-svc`)
- **Databases** (custodian Marcus; members Jamal; max 120, default 30): Prod PostgreSQL (`pg_admin`), Staging MySQL (`root`), Redis cluster (`default`)
- **Security Tools** (custodian Elena; member Priya; max 60, default 15, **non-member requests not allowed**): SIEM admin, Firewall management (`fwadmin`), EDR console
- **Finance Apps** (custodian Sofia; no members yet; max 60): Payroll portal, Accounting software admin, Corporate bank portal (view-only user)

**Personal credentials:** 2–4 per person, e.g. Priya's "Grafana personal", Jamal's "GitHub deploy token", Sofia's "Expense tool".

**Pre-paired:** every pairing required by the groups above (members ↔ custodians, custodians ↔ co-custodians), plus Jamal ↔ Sofia as a personal-sharing example. Tom is paired with nobody.

**Seeded history** (so the dashboards and logs aren't empty):
- Jamal has an **active lease** on Prod PostgreSQL (auto-approved, ~45 min left at startup).
- Marcus has a **pending request** in Priya's queue for the Backup server, 8 h requested, which exceeds policy and so needs manual approval.
- Jamal has a **pending request** in Sofia's queue for her personal "Expense tool".
- An **expired lease** of AWS root to Marcus yesterday, which raised a **Rotation due** task on Priya's and Elena's nodes.
- A **denied request** from Jamal to Elena for SIEM admin (non-member).
- ~30 backdated audit events per node with valid hash chains and signatures.

**How seeding works:** a seed module defines the whole team. Each container runs with `NODE_ID=<name>` and, if its data volume is empty and `DEMO_MODE=1`, builds *its own* state from the shared seed definition. Keys are derived deterministically from `DEMO_SEED` + node id, so all containers agree on each other's public keys without talking. **Deterministic keys are demo-only**: the node refuses to start with `DEMO_SEED` unless `DEMO_MODE=1`, and shows a red "DEMO — keys are not secret" banner. A non-demo node generates random keys. Expiry and timestamps in seed history are relative to first boot. `docker compose down -v` resets. In `DEMO_MODE`, each node unlocks its service key on boot using the demo password, so the seeded team is reachable immediately. The UI still starts locked.

## 10. Docker

- One multi-stage `Dockerfile`: Node stage builds the React UI, Python slim stage runs the node as a non-root user. Data lives at `/data` (volume).
- `docker-compose.yml` defines six services (priya…tom) on one bridge network. UIs map to `127.0.0.1:8001…8006`, and peer ports are internal, with hostnames for addressing.
- `docker-compose.lan.yml` (or a documented `docker run`) runs a **single fresh, non-demo node** on a second computer: maps UI to `127.0.0.1:8000` and the peer port `7600` on all interfaces, and sets `ADVERTISE_ADDR=<this PC's LAN IP>:7600`.
- To let a seeded node on computer 1 accept a pairing from computer 2, compose also publishes one seeded node's peer port (Tom's, `0.0.0.0:7606→7600`, since Tom is the unpaired demo user) to the LAN. The README documents the Windows Firewall rule to allow it.
- **Demo-key warning:** a node with `DEMO_MODE` off must detect a demo identity during pairing. Demo identity cards carry a `demo: true` flag and are signed by a key that can be checked against `DEMO_SEED`-derived keys. When it detects one, the node shows a blocking warning ("This peer uses publicly computable demo keys — anyone on this network can impersonate it"), and pairing goes ahead only if the user ticks "I understand, this is a test". The contact is then marked with a permanent DEMO badge.
- The README walks through: start the demo, log in as several people in separate browser tabs, run the scripted demo scenario, then pair across two computers.

## 11. Testing

- Unit: crypto helpers, vault wrap/unwrap, log chain and verify, policy decisions (auto-approve rules, version-signing rules).
- Protocol: an in-process **MITM proxy test** that relays and substitutes keys during pairing and must produce mismatched SAS. An attempted SAS-grinding MITM must fail because of the commit. Post-pairing, an unpinned key must fail the handshake. Replay of a captured message must be rejected. A tampered frame must fail AEAD.
- Integration: two or three nodes in one test process over localhost TCP, covering pair → request → auto-approve → lease → expire → receipt → rotation task.
- A smoke test that the compose stack boots and every seeded node's log verifies.

## 12. Decided vs. left to the builder

**Decided with the user:** decentralized (no server); medium team; approach B (custodians + auto-approve + leases); SAS pairing against MITM; expiry deletes the copy and raises a rotation reminder; ServiceNow-like UI; seed data; Docker; Bluetooth deferred because Docker can't reach it.

**My calls (user may override):** Python/FastAPI/React stack; Noise_KK plus custom commit-reveal pairing; Argon2id params; metadata plaintext at rest; the P2PSec seed team; the pea logo artwork; deterministic demo keys; six-node compose; UDP beacon discovery; Tom as the cross-machine pairing target.

**Left to the builder:** module layout, DB schema details, SSE vs polling, the React component library (styling must read as ServiceNow-like), exact UI copy, retry/backoff timings within reason.
