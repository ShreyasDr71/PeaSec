"""Settings from environment variables."""
from __future__ import annotations

import os
from dataclasses import dataclass


@dataclass
class Settings:
    node_id: str = "node"
    data_dir: str = "./data"
    ui_host: str = "127.0.0.1"
    ui_port: int = 8000
    peer_host: str = "0.0.0.0"
    peer_port: int = 7600
    advertise_addr: str = ""
    beacon_port: int = 7601
    beacon: bool = True
    demo_mode: bool = False
    demo_seed: str = ""
    allowed_hosts: tuple[str, ...] = ("127.0.0.1", "localhost")
    idle_lock_seconds: int = 600

    @classmethod
    def from_env(cls) -> "Settings":
        env = os.environ.get
        s = cls(
            node_id=env("NODE_ID", "node"),
            data_dir=env("DATA_DIR", "./data"),
            ui_host=env("UI_HOST", "127.0.0.1"),
            ui_port=int(env("UI_PORT", "8000")),
            peer_port=int(env("PEER_PORT", "7600")),
            advertise_addr=env("ADVERTISE_ADDR", ""),
            beacon=env("BEACON", "1") == "1",
            demo_mode=env("DEMO_MODE", "0") == "1",
            demo_seed=env("DEMO_SEED", ""),
            allowed_hosts=tuple(h.strip() for h in env("ALLOWED_HOSTS", "127.0.0.1,localhost").split(",") if h.strip()),
            idle_lock_seconds=int(env("IDLE_LOCK_SECONDS", "600")),
        )
        if s.demo_seed and not s.demo_mode:
            raise SystemExit("DEMO_SEED is set but DEMO_MODE is not 1: refusing to start with public demo keys.")
        return s
