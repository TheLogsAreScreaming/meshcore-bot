#!/usr/bin/env python3
"""On-demand nearby repeater test.

One action that asks every repeater in direct radio range to answer, then lists
the ones that did, strongest signal first. It is the quick "who can hear me
from here?" check an operator runs after moving the node or changing the
antenna, and it is reachable three ways:

* the ``nearby`` bot command (DM or channel),
* the web dashboard's Radio page ("Test nearby repeaters"),
* the Mac app's Bot menu, which opens that dashboard page.

The radio work is the same zero-hop node-discover request the scheduled
neighbors cycle uses (:func:`modules.neighbors_discovery.discover_neighbors`),
so the firmware contract, tag checking and reconnect handling live in one
place. Unlike that cycle this needs no packet-capture service, records nothing
to MQTT, and uses a short listen window, because a person is waiting for it.

Every run still costs airtime for the whole mesh (each repeater in range sends
a reply), so one :class:`NearbyRepeaterProbe` per bot rations runs: one at a
time, and a minimum gap between runs whichever trigger asks.
"""

from __future__ import annotations

import asyncio
import time
from dataclasses import dataclass
from typing import Any, Optional

from .neighbors_discovery import (
    MIN_DISCOVER_WINDOW,
    NeighborsConfig,
    discover_neighbors,
)
from .security_utils import sanitize_name

CONFIG_SECTION = "Nearby_Command"

DEFAULT_LISTEN_SECONDS = 15.0
MAX_LISTEN_SECONDS = 60.0
DEFAULT_MIN_GAP_SECONDS = 120.0
# Below this the "rationing" stops meaning anything: a script could ask every
# few seconds and keep every repeater in range busy answering.
MIN_GAP_FLOOR_SECONDS = 30.0
REQUEST_TIMEOUT_SECONDS = 20.0

# Refusal reasons. Stable strings: the dashboard and tests key off them.
REASON_NOT_CONNECTED = "not_connected"
REASON_BUSY = "busy"
REASON_COOLDOWN = "cooldown"
REASON_SEND_FAILED = "send_failed"
REASON_ERROR = "error"


@dataclass
class NearbyRepeater:
    """One repeater that answered the probe."""

    pubkey: str
    name: str
    snr: float

    @property
    def prefix(self) -> str:
        """First byte of the public key, as path hashes show it (e.g. ``a1``)."""
        return self.pubkey[:2]

    def to_dict(self) -> dict[str, Any]:
        return {
            "pubkey": self.pubkey,
            "prefix": self.prefix,
            "name": self.name,
            "snr": round(self.snr, 2),
        }


def clamp_listen_seconds(value: float) -> float:
    """Keep the listen window between the discover floor and one minute."""
    try:
        value = float(value)
    except (TypeError, ValueError):
        return DEFAULT_LISTEN_SECONDS
    if value != value:  # NaN
        return DEFAULT_LISTEN_SECONDS
    return max(MIN_DISCOVER_WINDOW, min(MAX_LISTEN_SECONDS, value))


def clamp_min_gap_seconds(value: float) -> float:
    """Never allow back-to-back probes faster than the floor."""
    try:
        value = float(value)
    except (TypeError, ValueError):
        return DEFAULT_MIN_GAP_SECONDS
    if value != value:
        return DEFAULT_MIN_GAP_SECONDS
    return max(MIN_GAP_FLOOR_SECONDS, value)


def _contact_name(meshcore: Any, pubkey: str) -> Optional[str]:
    """Name from the radio's contact table, if this repeater is a contact."""
    contacts = getattr(meshcore, "contacts", None)
    if not isinstance(contacts, dict):
        return None
    entry = contacts.get(pubkey) or contacts.get(pubkey.upper())
    if entry is None:
        for key, value in contacts.items():
            if str(key).lower() == pubkey:
                entry = value
                break
    if not isinstance(entry, dict):
        return None
    name = entry.get("adv_name") or entry.get("name")
    return str(name) if name else None


def _tracked_name(bot: Any, pubkey: str) -> Optional[str]:
    """Name from the bot's advert-tracking table, for repeaters not in contacts."""
    db = getattr(bot, "db_manager", None)
    query = getattr(db, "execute_query", None)
    if not callable(query) or asyncio.iscoroutinefunction(query):
        return None
    try:
        rows = query(
            "SELECT name FROM complete_contact_tracking WHERE lower(public_key) = ? LIMIT 1",
            (pubkey,),
        )
    except Exception:
        return None
    if rows and isinstance(rows[0], dict) and rows[0].get("name"):
        return str(rows[0]["name"])
    return None


def resolve_name(bot: Any, meshcore: Any, pubkey: str) -> str:
    """Best known display name for *pubkey*; falls back to its key prefix."""
    name = _contact_name(meshcore, pubkey) or _tracked_name(bot, pubkey)
    if name:
        return sanitize_name(name, max_length=32)
    return pubkey[:8]


def format_snr(snr: float) -> str:
    return f"{snr:+.1f}dB"


def format_reply(repeaters: list[NearbyRepeater], max_bytes: int,
                 *, header: str = "Nearby repeaters") -> str:
    """One mesh-sized line: ``Nearby repeaters (3): RptA a1 +9.5dB, ...``.

    Entries that do not fit in *max_bytes* (UTF-8) are summarised as
    ``+N more`` so the reply is always a single message.
    """
    if not repeaters:
        return ""
    prefix = f"{header} ({len(repeaters)}): "
    parts: list[str] = []
    for index, rep in enumerate(repeaters):
        part = f"{rep.name} {rep.prefix} {format_snr(rep.snr)}"
        remaining = len(repeaters) - index - 1
        candidate = prefix + ", ".join(parts + [part])
        tail = f", +{remaining} more" if remaining else ""
        if len((candidate + tail).encode("utf-8")) > max_bytes:
            left = len(repeaters) - index
            more = f"+{left} more"
            text = prefix + ", ".join(parts + [more]) if parts else prefix + more
            return _truncate_utf8(text, max_bytes)
        parts.append(part)
    return _truncate_utf8(prefix + ", ".join(parts), max_bytes)


def _truncate_utf8(text: str, max_bytes: int) -> str:
    encoded = text.encode("utf-8")
    if len(encoded) <= max_bytes:
        return text
    return encoded[:max(0, max_bytes)].decode("utf-8", errors="ignore")


class NearbyRepeaterProbe:
    """Runs the probe and rations it. One instance per bot (see :func:`get_probe`)."""

    def __init__(self, bot: Any) -> None:
        self.bot = bot
        self.logger = bot.logger
        self._lock = asyncio.Lock()
        self._running = False
        self.last_run_at = 0.0
        self.last_result: Optional[dict[str, Any]] = None

    # -- config -------------------------------------------------------------

    def _config_float(self, key: str, fallback: float) -> float:
        config = getattr(self.bot, "config", None)
        try:
            if config is not None and config.has_section(CONFIG_SECTION):
                return config.getfloat(CONFIG_SECTION, key, fallback=fallback)
        except (TypeError, ValueError):
            pass
        return fallback

    @property
    def listen_seconds(self) -> float:
        return clamp_listen_seconds(self._config_float("listen_seconds", DEFAULT_LISTEN_SECONDS))

    @property
    def min_gap_seconds(self) -> float:
        return clamp_min_gap_seconds(self._config_float("min_gap_seconds", DEFAULT_MIN_GAP_SECONDS))

    # -- state --------------------------------------------------------------

    @property
    def running(self) -> bool:
        return self._running

    def cooldown_remaining(self, now: Optional[float] = None) -> float:
        if not self.last_run_at:
            return 0.0
        now = time.time() if now is None else now
        return max(0.0, self.last_run_at + self.min_gap_seconds - now)

    def _neighbors_cycle_active(self) -> bool:
        """The scheduled neighbors cycle sends the same request; don't overlap it."""
        service = getattr(self.bot, "packet_capture_service", None)
        return bool(getattr(service, "neighbors_cycle_active", False))

    def refusal(self) -> Optional[dict[str, Any]]:
        """Why a run would be refused right now, or None if it may start."""
        meshcore = getattr(self.bot, "meshcore", None)
        if not getattr(self.bot, "connected", False) or meshcore is None:
            return _result(False, REASON_NOT_CONNECTED, error="Radio not connected")
        if self._running or self._lock.locked() or self._neighbors_cycle_active():
            return _result(False, REASON_BUSY, error="A repeater test is already running")
        remaining = self.cooldown_remaining()
        if remaining > 0:
            return _result(
                False, REASON_COOLDOWN,
                error=f"A repeater test ran recently; try again in {int(remaining) + 1}s",
                retry_after=int(remaining) + 1,
            )
        return None

    # -- run ----------------------------------------------------------------

    async def run(self) -> dict[str, Any]:
        """Probe once. Always returns a result dict; never raises.

        ``{"ok": True, "repeaters": [...], "listened": 15.0, ...}`` on success,
        ``{"ok": False, "reason": ..., "error": ...}`` when refused or failed.
        """
        refused = self.refusal()
        if refused is not None:
            return refused

        async with self._lock:
            # A caller that queued on the lock behind a finished run must not
            # start a second probe inside the gap.
            remaining = self.cooldown_remaining()
            if remaining > 0:
                return _result(
                    False, REASON_COOLDOWN,
                    error=f"A repeater test ran recently; try again in {int(remaining) + 1}s",
                    retry_after=int(remaining) + 1,
                )
            self._running = True
            # Claim the gap now, not on completion, so a failure part-way
            # through still rations retries.
            self.last_run_at = time.time()
            try:
                result = await self._probe()
            except asyncio.CancelledError:
                raise
            except Exception as exc:
                self.logger.error(f"Nearby repeater test failed: {exc}", exc_info=True)
                result = _result(False, REASON_ERROR, error=str(exc))
            finally:
                self._running = False
            self.last_result = result
            return result

    async def _probe(self) -> dict[str, Any]:
        meshcore = self.bot.meshcore
        listen = self.listen_seconds
        cfg = NeighborsConfig(
            discover_window=listen,
            command_timeout=REQUEST_TIMEOUT_SECONDS,
        )
        self_info = getattr(meshcore, "self_info", None) or {}
        self_pubkey = self_info.get("public_key") if isinstance(self_info, dict) else None

        def still_valid() -> bool:
            return getattr(self.bot, "meshcore", None) is meshcore and bool(
                getattr(self.bot, "connected", False)
            )

        self.logger.info(f"Nearby repeater test: probing, listening for {listen:.0f}s")
        started = time.time()
        entries = await discover_neighbors(
            meshcore, cfg, self_pubkey, self.logger, still_valid=still_valid,
        )
        if entries is None:
            return _result(
                False, REASON_SEND_FAILED,
                error="The radio did not send the discover request "
                      "(firmware may not support it, or the link dropped)",
            )

        repeaters = [
            NearbyRepeater(pubkey=e.pubkey, name=resolve_name(self.bot, meshcore, e.pubkey), snr=e.snr)
            for e in entries
        ]
        repeaters.sort(key=lambda r: (-r.snr, r.pubkey))
        self.logger.info(f"Nearby repeater test: {len(repeaters)} repeater(s) answered")
        result = _result(True, None)
        result.update({
            "repeaters": [r.to_dict() for r in repeaters],
            "count": len(repeaters),
            "listened": listen,
            "started_at": started,
            "finished_at": time.time(),
        })
        return result


def _result(ok: bool, reason: Optional[str], **extra: Any) -> dict[str, Any]:
    out: dict[str, Any] = {"ok": ok, "reason": reason, "repeaters": [], "count": 0}
    out.update(extra)
    return out


def repeaters_from_result(result: dict[str, Any]) -> list[NearbyRepeater]:
    """Rebuild :class:`NearbyRepeater` objects from a result dict."""
    out = []
    for item in result.get("repeaters") or []:
        try:
            out.append(NearbyRepeater(
                pubkey=str(item["pubkey"]), name=str(item["name"]), snr=float(item["snr"])
            ))
        except (KeyError, TypeError, ValueError):
            continue
    return out


def get_probe(bot: Any) -> NearbyRepeaterProbe:
    """The bot's shared probe, created on first use.

    Shared so the command, the dashboard and any other trigger all respect the
    same one-at-a-time rule and minimum gap.
    """
    probe = getattr(bot, "_nearby_repeater_probe", None)
    if not isinstance(probe, NearbyRepeaterProbe):
        probe = NearbyRepeaterProbe(bot)
        bot._nearby_repeater_probe = probe
    return probe
