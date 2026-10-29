"""A P2PSec node: wires vault, audit, engine, peer service and background loops."""
from __future__ import annotations

import asyncio
import base64
import logging
import os
import socket

from . import db
from .audit import AuditLog
from .channel import ReplayGuard
from .config import Settings
from .crypto import Identity
from .engine import Engine
from .peer import PeerService
from .vault import BadPassword, Vault

log = logging.getLogger("p2psec.node")
DEMO_PASSWORD = "p2psec-demo"
SWEEP_EVERY, FLUSH_EVERY, PING_EVERY = 15, 10, 30


class Node:
    def __init__(self, settings: Settings):
        self.settings = settings
        os.makedirs(settings.data_dir, exist_ok=True)
        self.conn = db.open_db(os.path.join(settings.data_dir, "node.db"))
        self.vault: Vault | None = None
        self.identity: Identity | None = None
        self.audit: AuditLog | None = None
        self.engine: Engine | None = None
        self.guard = ReplayGuard(self.conn)
        self.peer = PeerService(self)
        self.beacon = None
        self.peer_port = settings.peer_port
        self.advertise_addr = settings.advertise_addr or f"{socket.gethostname()}:{settings.peer_port}"
        self._loops: list[asyncio.Task] = []

    # --- state ------------------------------------------------------------------

    @property
    def initialized(self) -> bool:
        return db.get_meta(self.conn, "vault") is not None

    @property
    def profile(self) -> dict:
        return db.get_meta(self.conn, "profile", {"name": "", "title": "", "dept": ""})

    @property
    def fpr(self) -> str:
        return (db.get_meta(self.conn, "identity_pub") or {}).get("fpr", "")

    @property
    def service_ready(self) -> bool:
        return bool(self.vault and self.vault.service_unlocked and self.engine)

    @property
    def personal_unlocked(self) -> bool:
        return bool(self.vault and self.vault.personal_unlocked)

    # --- setup / unlock -----------------------------------------------------------

    def setup(self, password: str, profile: dict, identity: Identity | None = None,
              params: dict | None = None, ts: float | None = None) -> None:
        if self.initialized:
            raise RuntimeError("already initialized")
        if len(password) < 8:
            raise ValueError("master password must be at least 8 characters")
        identity = identity or Identity.generate()
        vault, header = Vault.create(password, params=params)
        db.set_meta(self.conn, "vault", header)
        db.set_meta(self.conn, "profile", {k: profile.get(k, "") for k in ("name", "title", "dept")})
        db.set_meta(self.conn, "identity_pub", {"fpr": identity.fingerprint(),
                                                "ed": base64.b64encode(identity.ed_pub_bytes()).decode(),
                                                "x": base64.b64encode(identity.x_pub_bytes()).decode()})
        ct = vault.enc("service", "identity", "self", identity.private_bytes())
        db.set_meta(self.conn, "identity_ct", base64.b64encode(ct).decode())
        db.set_meta(self.conn, "demo", self.settings.demo_mode)
        self._load(vault, identity)
        self.audit.append("VAULT_CREATED", {"node": self.settings.node_id}, {"demo": self.settings.demo_mode}, ts=ts)

    def _load(self, vault: Vault, identity: Identity) -> None:
        self.vault, self.identity = vault, identity
        self.audit = AuditLog(self.conn, identity)
        self.engine = Engine(self.conn, vault, self.audit, identity, self.profile)

    async def unlock(self, password: str) -> None:
        header = db.get_meta(self.conn, "vault")
        if header is None:
            raise RuntimeError("not initialized")
        try:
            if self.vault is None or not self.vault.service_unlocked:
                vault = await asyncio.to_thread(Vault.unlock, header, password)
                raw = vault.dec("service", "identity", "self", base64.b64decode(db.get_meta(self.conn, "identity_ct")))
                self._load(vault, Identity.from_private_bytes(raw))
            else:
                await asyncio.to_thread(self.vault.unlock_personal, header, password)
        except BadPassword:
            if self.audit:
                self.audit.append("UNLOCK_FAILED", {"node": self.settings.node_id})
            else:
                db.set_meta(self.conn, "failed_unlocks", db.get_meta(self.conn, "failed_unlocks", 0) + 1)
            raise
        failed = db.get_meta(self.conn, "failed_unlocks", 0)
        if failed:
            self.audit.append("UNLOCK_FAILED", {"node": self.settings.node_id},
                              {"count": failed, "note": "failed attempts while the node was fully locked"})
            db.set_meta(self.conn, "failed_unlocks", 0)
        self.audit.append("UNLOCKED", {"node": self.settings.node_id})
        self.engine.profile = self.profile
        self._start_loops()

    def soft_lock(self) -> None:
        if self.vault and self.vault.personal_unlocked:
            self.vault.soft_lock()
            self.audit.append("LOCKED", {"node": self.settings.node_id}, {"mode": "soft"})

    def full_lock(self) -> None:
        if self.vault:
            self.audit.append("LOCKED", {"node": self.settings.node_id}, {"mode": "full"})
            self.vault.full_lock()
        self._stop_loops()
        self.vault = self.identity = self.engine = None

    def change_password(self, old: str, new: str) -> None:
        if len(new) < 8:
            raise ValueError("master password must be at least 8 characters")
        header = db.get_meta(self.conn, "vault")
        db.set_meta(self.conn, "vault", self.vault.rewrap(header, old, new))
        self.audit.append("PASSWORD_CHANGED", {"node": self.settings.node_id})

    def set_profile(self, profile: dict) -> None:
        db.set_meta(self.conn, "profile", {k: str(profile.get(k, ""))[:100] for k in ("name", "title", "dept")})
        if self.engine:
            self.engine.profile = self.profile

    # --- services -------------------------------------------------------------------

    async def start_peer(self) -> None:
        port = await self.peer.start(self.settings.peer_host, self.settings.peer_port)
        if not self.settings.advertise_addr:
            self.peer_port = port
            self.advertise_addr = f"{socket.gethostname()}:{port}" if self.settings.peer_port else f"127.0.0.1:{port}"
        if self.settings.beacon:
            from .discovery import Beacon
            self.beacon = Beacon(self)
            await self.beacon.start()

    async def boot(self) -> None:
        if not self.initialized and self.settings.demo_mode and self.settings.demo_seed:
            from . import seed
            seed.build(self)
            self.full_lock()
        await self.start_peer()
        if self.settings.demo_mode and self.initialized:
            await self.unlock(DEMO_PASSWORD)
            self.soft_lock()

    def _start_loops(self) -> None:
        if self._loops:
            return
        loop = asyncio.get_running_loop()
        self._loops = [loop.create_task(self._every(SWEEP_EVERY, self._sweep, first=0)),
                       loop.create_task(self._every(FLUSH_EVERY, self.peer.flush_outbox, first=2)),
                       loop.create_task(self._every(PING_EVERY, self.peer.ping_all, first=1))]

    def _stop_loops(self) -> None:
        for t in self._loops:
            t.cancel()
        self._loops = []

    async def _every(self, seconds: float, fn, first: float) -> None:
        await asyncio.sleep(first)
        while True:
            try:
                if self.service_ready:
                    await fn()
            except asyncio.CancelledError:
                raise
            except Exception:
                log.exception("background task %s failed", getattr(fn, "__name__", fn))
            await asyncio.sleep(seconds)

    async def _sweep(self) -> None:
        outs = self.engine.sweep()
        if outs:
            await self.peer.send_outs(outs)

    async def act(self, outs) -> None:
        """Deliver an action's outbound messages in the background."""
        if outs:
            self.peer.spawn(self.peer.send_outs(outs))

    async def shutdown(self) -> None:
        self._stop_loops()
        await self.peer.stop()
        if self.beacon:
            self.beacon.stop()
