#!/usr/bin/env python3
"""
Outbound event webhooks for MeshCore Bot

Sends selected mesh events to HTTP endpoints you configure, as JSON POSTs, so
other systems (home automation, dashboards, logging, chat bridges) can react to
what the bot hears. Off by default.

Config section ``[Event_Webhooks]``::

    enabled  = false
    urls     = https://example.com/hook          # comma-separated
    events   = message_received,command_run     # also: node_seen
    secret   =                                  # HMAC-SHA256 signing key
    include_dm_text = false                     # forward DM wording?
    channels =                                  # message_received filter
    node_seen_interval_seconds = 300            # per-node throttle
    timeout_seconds = 5

Each POST body::

    {"event": "message_received", "sent_at": "2026-11-13T18:00:00+00:00",
     "bot": "MyBot", "data": {...}}

Headers: ``X-MeshCore-Event: <event>`` and, when ``secret`` is set,
``X-MeshCore-Signature: sha256=<hex HMAC of the raw body>`` so the receiver can
check the request really came from this bot.

Delivery is best effort: events queue in memory (bounded, oldest dropped when
full), each URL gets one retry on a network error or 5xx, and nothing is ever
allowed to slow down the bot's mesh handling.

To *receive* webhooks (send a mesh message from an HTTP POST) see the separate
``[Webhook]`` service (modules/service_plugins/webhook_service.py).
"""

from __future__ import annotations

import asyncio
import hashlib
import hmac
import json
import time
from collections import OrderedDict
from datetime import datetime, timezone
from typing import Any, Optional
from urllib.parse import urlsplit

from ..mesh_events import (
    ALL_EVENTS,
    EVENT_MESSAGE_RECEIVED,
    EVENT_NODE_SEEN,
    get_event_bus,
)
from .base_service import BaseServicePlugin

try:
    import aiohttp
    AIOHTTP_AVAILABLE = True
except ImportError:  # pragma: no cover - aiohttp is a core dependency
    aiohttp = None  # type: ignore[assignment]
    AIOHTTP_AVAILABLE = False

SECTION = "Event_Webhooks"
DEFAULT_EVENTS = "message_received,command_run"
QUEUE_MAX = 200
RETRY_DELAY_SECONDS = 2.0
MAX_TRACKED_NODES = 2000
LOOPBACK_HOSTS = {"localhost", "127.0.0.1", "::1"}


def parse_urls(raw: str) -> tuple[list[str], list[str]]:
    """Split the ``urls`` setting into (valid, rejected). Only http(s) URLs with a host."""
    valid: list[str] = []
    rejected: list[str] = []
    for part in (raw or "").split(","):
        url = part.strip()
        if not url:
            continue
        parts = urlsplit(url)
        if parts.scheme in ("http", "https") and parts.hostname:
            if url not in valid:
                valid.append(url)
        else:
            rejected.append(url)
    return valid, rejected


def parse_events(raw: str) -> tuple[set[str], list[str]]:
    """Split the ``events`` setting into (known events, unknown names)."""
    known: set[str] = set()
    unknown: list[str] = []
    for part in (raw or "").split(","):
        name = part.strip().lower()
        if not name:
            continue
        if name in ALL_EVENTS:
            known.add(name)
        else:
            unknown.append(name)
    return known, unknown


def redact_url(url: str) -> str:
    """Scheme and host only: webhook URLs often carry a token in the path or query."""
    parts = urlsplit(url)
    return f"{parts.scheme}://{parts.hostname or '?'}/…"


def sign(secret: str, body: bytes) -> str:
    return "sha256=" + hmac.new(secret.encode("utf-8"), body, hashlib.sha256).hexdigest()


class EventWebhookService(BaseServicePlugin):
    """POST selected mesh events to user-configured HTTP endpoints."""

    config_section = SECTION
    description = "Outbound webhooks — POST mesh events (messages, nodes seen, commands) to your URLs"

    settings_schema = [
        {"key": "urls", "label": "Webhook URLs", "type": "list", "default": "",
         "help": "Comma-separated http(s) URLs. Each receives every selected event as a JSON POST."},
        {"key": "events", "label": "Events", "type": "list", "default": DEFAULT_EVENTS,
         "help": "Any of: message_received, node_seen, command_run."},
        {"key": "secret", "label": "Signing secret", "type": "str", "default": "",
         "help": "If set, each POST carries X-MeshCore-Signature: sha256=<HMAC of the body>."},
        {"key": "include_dm_text", "label": "Include DM text", "type": "bool", "default": False,
         "help": "Off: DMs to the bot are reported without their wording."},
        {"key": "channels", "label": "Channels", "type": "list", "default": "",
         "help": "Only report channel messages from these channels. Empty = all."},
        {"key": "node_seen_interval_seconds", "label": "Node-seen throttle (s)", "type": "int",
         "min": 0, "default": 300, "help": "Report each node at most once per this many seconds."},
        {"key": "timeout_seconds", "label": "Timeout (s)", "type": "int", "min": 1, "max": 60,
         "default": 5, "help": "Per-request timeout."},
    ]

    def __init__(self, bot: Any) -> None:
        super().__init__(bot)
        cfg = bot.config
        if not cfg.has_section(SECTION):
            self.enabled = False
            self._load_defaults()
            return
        self.enabled = cfg.getboolean(SECTION, "enabled", fallback=False)
        self.urls, rejected = parse_urls(cfg.get(SECTION, "urls", fallback=""))
        self.events, unknown = parse_events(cfg.get(SECTION, "events", fallback=DEFAULT_EVENTS))
        self.secret = cfg.get(SECTION, "secret", fallback="").strip()
        self.include_dm_text = cfg.getboolean(SECTION, "include_dm_text", fallback=False)
        raw_channels = cfg.get(SECTION, "channels", fallback="")
        self.channels = {c.strip().removeprefix("#").lower() for c in raw_channels.split(",") if c.strip()}
        self.node_seen_interval = max(0, cfg.getint(SECTION, "node_seen_interval_seconds", fallback=300))
        self.timeout = min(60, max(1, cfg.getint(SECTION, "timeout_seconds", fallback=5)))
        self._init_state()

        if not self.enabled:
            return
        for url in rejected:
            self.logger.warning(f"Event webhooks: ignoring invalid URL (must be http or https): {redact_url(url)}")
        for name in unknown:
            self.logger.warning(f"Event webhooks: ignoring unknown event '{name}' (known: {', '.join(ALL_EVENTS)})")
        if not AIOHTTP_AVAILABLE:
            self.logger.error("Event webhooks need aiohttp (pip install aiohttp); disabled")
            self.enabled = False
        elif not self.urls:
            self.logger.warning("Event webhooks enabled but no valid urls are set; disabled")
            self.enabled = False
        elif not self.events:
            self.logger.warning("Event webhooks enabled but no known events are selected; disabled")
            self.enabled = False

    def _load_defaults(self) -> None:
        self.urls = []
        self.events = set()
        self.secret = ""
        self.include_dm_text = False
        self.channels = set()
        self.node_seen_interval = 300
        self.timeout = 5
        self._init_state()

    def _init_state(self) -> None:
        self._queue: Optional[asyncio.Queue] = None
        self._worker: Optional[asyncio.Task] = None
        self._session: Any = None
        self._node_last_sent: OrderedDict[str, float] = OrderedDict()
        self.sent = 0
        self.failed = 0
        self.dropped = 0

    # ------------------------------------------------------------------
    # Lifecycle
    # ------------------------------------------------------------------

    async def start(self) -> None:
        if not self.enabled:
            return
        self._queue = asyncio.Queue(maxsize=QUEUE_MAX)
        self._session = aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=self.timeout))
        self._worker = asyncio.create_task(self._deliver_loop())
        get_event_bus(self.bot).subscribe(self.on_event)
        self._running = True
        for url in self.urls:
            if urlsplit(url).scheme == "http" and (urlsplit(url).hostname or "") not in LOOPBACK_HOSTS:
                self.logger.warning(
                    f"Event webhooks: {redact_url(url)} is plain http — mesh traffic will cross "
                    "the network unencrypted. Prefer https."
                )
        self.logger.info(
            f"Event webhooks: sending {', '.join(sorted(self.events))} to {len(self.urls)} URL(s)"
            f"{' (signed)' if self.secret else ''}"
        )

    async def stop(self) -> None:
        self._running = False
        get_event_bus(self.bot).unsubscribe(self.on_event)
        if self._worker is not None:
            self._worker.cancel()
            try:
                await self._worker
            except (asyncio.CancelledError, Exception):
                pass
            self._worker = None
        if self._session is not None:
            try:
                await self._session.close()
            except Exception:
                pass
            self._session = None

    # ------------------------------------------------------------------
    # Event intake (runs on the bot's loop; must stay cheap)
    # ------------------------------------------------------------------

    def on_event(self, event: str, data: dict[str, Any]) -> None:
        if not self._running or self._queue is None or event not in self.events:
            return
        payload = self.filter_event(event, data)
        if payload is None:
            return
        envelope = {
            "event": event,
            "sent_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
            "bot": self._bot_name(),
            "data": payload,
        }
        if self._queue.full():
            try:
                self._queue.get_nowait()
                self._queue.task_done()
                self.dropped += 1
            except asyncio.QueueEmpty:
                pass
        self._queue.put_nowait(envelope)

    def filter_event(self, event: str, data: dict[str, Any]) -> Optional[dict[str, Any]]:
        """Apply privacy and volume rules. Returns the data to send, or None to skip."""
        data = dict(data)
        if event == EVENT_MESSAGE_RECEIVED:
            if data.get("is_dm"):
                if not self.include_dm_text:
                    data["text"] = None
            elif self.channels:
                channel = str(data.get("channel") or "").removeprefix("#").lower()
                if channel not in self.channels:
                    return None
        elif event == EVENT_NODE_SEEN:
            key = str(data.get("public_key") or "")
            if not key:
                return None
            now = time.monotonic()
            last = self._node_last_sent.get(key)
            if last is not None and self.node_seen_interval and now - last < self.node_seen_interval:
                return None
            self._node_last_sent[key] = now
            self._node_last_sent.move_to_end(key)
            while len(self._node_last_sent) > MAX_TRACKED_NODES:
                self._node_last_sent.popitem(last=False)
        else:  # command_run
            if data.get("is_dm") and not self.include_dm_text:
                data["text"] = None
                data["response"] = None
        return data

    def _bot_name(self) -> str:
        try:
            return self.bot.config.get("Bot", "bot_name", fallback="")
        except Exception:
            return ""

    # ------------------------------------------------------------------
    # Delivery
    # ------------------------------------------------------------------

    def build_request(self, envelope: dict[str, Any]) -> tuple[bytes, dict[str, str]]:
        body = json.dumps(envelope, separators=(",", ":"), ensure_ascii=False, default=str).encode("utf-8")
        headers = {
            "Content-Type": "application/json",
            "User-Agent": "MeshCoreBot-Webhooks/1",
            "X-MeshCore-Event": str(envelope.get("event", "")),
        }
        if self.secret:
            headers["X-MeshCore-Signature"] = sign(self.secret, body)
        return body, headers

    async def _deliver_loop(self) -> None:
        assert self._queue is not None
        while True:
            envelope = await self._queue.get()
            try:
                await self.deliver(envelope)
            except asyncio.CancelledError:
                raise
            except Exception as exc:
                self.logger.debug(f"Event webhooks: delivery error: {exc}")
            finally:
                self._queue.task_done()

    async def deliver(self, envelope: dict[str, Any]) -> None:
        body, headers = self.build_request(envelope)
        for url in self.urls:
            if await self._post_with_retry(url, body, headers):
                self.sent += 1
            else:
                self.failed += 1

    async def _post_with_retry(self, url: str, body: bytes, headers: dict[str, str]) -> bool:
        for attempt in (1, 2):
            status = await self._post(url, body, headers)
            if status is not None and 200 <= status < 300:
                return True
            if status is not None and 400 <= status < 500:
                # The receiver understood and refused; retrying will not help.
                self.logger.warning(f"Event webhooks: {redact_url(url)} rejected the event (HTTP {status})")
                return False
            if attempt == 1:
                await asyncio.sleep(RETRY_DELAY_SECONDS)
        self.logger.warning(
            f"Event webhooks: could not deliver to {redact_url(url)}"
            f"{f' (HTTP {status})' if status is not None else ''}"
        )
        return False

    async def _post(self, url: str, body: bytes, headers: dict[str, str]) -> Optional[int]:
        """POST once. Returns the HTTP status, or None on a network error."""
        if self._session is None:
            return None
        try:
            async with self._session.post(url, data=body, headers=headers, allow_redirects=False) as resp:
                return int(resp.status)
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            self.logger.debug(f"Event webhooks: POST to {redact_url(url)} failed: {type(exc).__name__}")
            return None
