#!/usr/bin/env python3
"""In-process mesh event hub.

A tiny publish/subscribe point so features that want to *observe* the mesh
(today: outbound webhooks) don't have to be wired into the message handler,
the repeater tracker and the command manager one by one.

Emitting is fire-and-forget and must never slow down or break the code that
emits: listeners are called synchronously only to hand the event over; any
coroutine they return runs as a background task, and every listener error is
logged at debug level and swallowed.

Event names are stable strings (they appear in webhook payloads):

* ``message_received`` -- a channel message or DM reached the bot.
* ``node_seen``        -- an advert from a node was tracked (not duplicates).
* ``command_run``      -- the bot executed a command for someone.
"""

from __future__ import annotations

import asyncio
import inspect
import logging
from typing import Any, Callable

EVENT_MESSAGE_RECEIVED = "message_received"
EVENT_NODE_SEEN = "node_seen"
EVENT_COMMAND_RUN = "command_run"
ALL_EVENTS = (EVENT_MESSAGE_RECEIVED, EVENT_NODE_SEEN, EVENT_COMMAND_RUN)

Listener = Callable[[str, dict[str, Any]], Any]


class MeshEventBus:
    """Fan-out of named events to listeners. Safe to call from the bot's loop."""

    def __init__(self, logger: logging.Logger | None = None) -> None:
        self.logger = logger or logging.getLogger(__name__)
        self._listeners: list[Listener] = []
        # Strong references so pending listener tasks are not garbage-collected.
        self._tasks: set[asyncio.Task] = set()

    @property
    def has_listeners(self) -> bool:
        return bool(self._listeners)

    def subscribe(self, listener: Listener) -> None:
        if listener not in self._listeners:
            self._listeners.append(listener)

    def unsubscribe(self, listener: Listener) -> None:
        if listener in self._listeners:
            self._listeners.remove(listener)

    def emit(self, event: str, data: dict[str, Any]) -> None:
        for listener in list(self._listeners):
            try:
                result = listener(event, data)
                if inspect.isawaitable(result):
                    try:
                        loop = asyncio.get_running_loop()
                    except RuntimeError:
                        # No running loop (e.g. called from a worker thread):
                        # close the coroutine instead of leaking a warning.
                        close = getattr(result, "close", None)
                        if callable(close):
                            close()
                        continue
                    task = asyncio.ensure_future(result, loop=loop)
                    self._tasks.add(task)
                    task.add_done_callback(self._tasks.discard)
            except Exception as exc:
                self.logger.debug(f"Mesh event listener failed for {event}: {exc}")


def get_event_bus(bot: Any) -> MeshEventBus:
    """The bot's event bus, created on first use."""
    bus = getattr(bot, "mesh_events", None)
    if not isinstance(bus, MeshEventBus):
        bus = MeshEventBus(getattr(bot, "logger", None))
        try:
            bot.mesh_events = bus
        except Exception:
            pass
    return bus


def emit(bot: Any, event: str, build: Callable[[], dict[str, Any]]) -> None:
    """Emit *event* if anyone is listening. *build* makes the payload lazily,
    so call sites pay nothing when no feature subscribes. Never raises."""
    try:
        bus = getattr(bot, "mesh_events", None)
        if not isinstance(bus, MeshEventBus) or not bus.has_listeners:
            return
        bus.emit(event, build())
    except Exception as exc:
        logger = getattr(bot, "logger", None)
        if logger is not None:
            logger.debug(f"Could not emit mesh event {event}: {exc}")


# ---------------------------------------------------------------------------
# Payload builders. Kept here so every emit site sends the same shape.
# ---------------------------------------------------------------------------

def _message_text(message: Any) -> Any:
    return getattr(message, "original_content", None) or getattr(message, "content", None)


def message_payload(message: Any) -> dict[str, Any]:
    """``message_received`` data for a MeshMessage."""
    return {
        "channel": None if getattr(message, "is_dm", False) else getattr(message, "channel", None),
        "is_dm": bool(getattr(message, "is_dm", False)),
        "sender": getattr(message, "sender_id", None),
        "sender_pubkey": getattr(message, "sender_pubkey", None),
        "text": _message_text(message),
        "hops": getattr(message, "hops", None),
        "path": getattr(message, "path", None),
        "snr": getattr(message, "snr", None),
        "rssi": getattr(message, "rssi", None),
        "timestamp": getattr(message, "timestamp", None),
    }


def command_payload(message: Any, command: str, ok: bool, response: Any = None) -> dict[str, Any]:
    """``command_run`` data: who ran what, where, and what the bot answered."""
    return {
        "command": command,
        "ok": bool(ok),
        "channel": None if getattr(message, "is_dm", False) else getattr(message, "channel", None),
        "is_dm": bool(getattr(message, "is_dm", False)),
        "sender": getattr(message, "sender_id", None),
        "sender_pubkey": getattr(message, "sender_pubkey", None),
        "text": _message_text(message),
        "response": response if isinstance(response, str) else None,
    }


def emit_command_run(bot: Any, message: Any, command: str, ok: bool, response: Any = None) -> None:
    """Emit ``command_run`` unless *message* is a synthetic, capture-only run."""
    if getattr(message, "capture_sink", None) is not None:
        return
    emit(bot, EVENT_COMMAND_RUN, lambda: command_payload(message, command, ok, response))
