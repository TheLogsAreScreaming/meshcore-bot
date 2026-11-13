"""Tests for outbound event webhooks (modules/service_plugins/event_webhook_service.py)."""

from __future__ import annotations

import asyncio
import hashlib
import hmac
import json
import logging
from configparser import ConfigParser
from types import SimpleNamespace

import pytest

from modules import mesh_events
from modules.service_plugins import event_webhook_service as ew
from modules.service_plugins.event_webhook_service import EventWebhookService


def make_bot(**settings):
    cfg = ConfigParser()
    cfg.add_section("Bot")
    cfg.set("Bot", "bot_name", "TestBot")
    cfg.add_section("Event_Webhooks")
    values = {"enabled": "true", "urls": "https://hooks.example.com/abc?token=s3cret"}
    values.update(settings)
    for key, value in values.items():
        cfg.set("Event_Webhooks", key, value)
    return SimpleNamespace(logger=logging.getLogger("test-event-webhooks"), config=cfg)


class FakeResponse:
    def __init__(self, status):
        self.status = status

    async def __aenter__(self):
        return self

    async def __aexit__(self, *exc):
        return False


class FakeSession:
    """Records POSTs; plays back a scripted list of statuses (or exceptions)."""

    def __init__(self, statuses=None):
        self.statuses = list(statuses or [])
        self.posts = []
        self.closed = False

    def post(self, url, data=None, headers=None, allow_redirects=True):
        self.posts.append({"url": url, "body": data, "headers": headers,
                           "allow_redirects": allow_redirects})
        outcome = self.statuses.pop(0) if self.statuses else 200
        if isinstance(outcome, Exception):
            raise outcome
        return FakeResponse(outcome)

    async def close(self):
        self.closed = True


@pytest.fixture(autouse=True)
def no_retry_delay(monkeypatch):
    monkeypatch.setattr(ew, "RETRY_DELAY_SECONDS", 0)


# -- config -----------------------------------------------------------------

def test_off_by_default_without_section():
    bot = SimpleNamespace(logger=logging.getLogger("t"), config=ConfigParser())
    assert EventWebhookService(bot).enabled is False


def test_off_when_enabled_is_false():
    assert EventWebhookService(make_bot(enabled="false")).enabled is False


def test_defaults():
    svc = EventWebhookService(make_bot())
    assert svc.enabled is True
    assert svc.events == {"message_received", "command_run"}
    assert svc.include_dm_text is False
    assert svc.secret == ""


def test_invalid_urls_and_events_are_dropped_and_disable_when_nothing_left(caplog):
    with caplog.at_level(logging.WARNING):
        svc = EventWebhookService(make_bot(urls="ftp://x, notaurl", events="message_received"))
    assert svc.urls == []
    assert svc.enabled is False
    svc = EventWebhookService(make_bot(events="bogus"))
    assert svc.enabled is False


def test_parse_helpers():
    urls, rejected = ew.parse_urls("https://a.example/x, http://127.0.0.1:9000/h, file:///etc, https://a.example/x")
    assert urls == ["https://a.example/x", "http://127.0.0.1:9000/h"]
    assert rejected == ["file:///etc"]
    events, unknown = ew.parse_events("Node_Seen, command_run, nope")
    assert events == {"node_seen", "command_run"} and unknown == ["nope"]


def test_redacted_url_hides_path_and_query():
    assert ew.redact_url("https://hooks.example.com/abc?token=s3cret") == "https://hooks.example.com/…"


# -- filtering --------------------------------------------------------------

def test_dm_text_is_withheld_unless_opted_in():
    svc = EventWebhookService(make_bot())
    out = svc.filter_event("message_received", {"is_dm": True, "text": "secret plans", "sender": "Al"})
    assert out["text"] is None and out["sender"] == "Al"
    svc = EventWebhookService(make_bot(include_dm_text="true"))
    assert svc.filter_event("message_received", {"is_dm": True, "text": "hi"})["text"] == "hi"


def test_dm_command_text_and_response_are_withheld():
    svc = EventWebhookService(make_bot())
    out = svc.filter_event("command_run", {"is_dm": True, "command": "wx", "text": "wx 06511",
                                           "response": "Sunny"})
    assert out["command"] == "wx" and out["text"] is None and out["response"] is None


def test_channel_filter():
    svc = EventWebhookService(make_bot(channels="#Alerts, general"))
    assert svc.filter_event("message_received", {"channel": "alerts", "text": "x"}) is not None
    assert svc.filter_event("message_received", {"channel": "#general", "text": "x"}) is not None
    assert svc.filter_event("message_received", {"channel": "random", "text": "x"}) is None


def test_node_seen_is_throttled_per_node():
    svc = EventWebhookService(make_bot(events="node_seen", node_seen_interval_seconds="300"))
    assert svc.filter_event("node_seen", {"public_key": "aa"}) is not None
    assert svc.filter_event("node_seen", {"public_key": "aa"}) is None
    assert svc.filter_event("node_seen", {"public_key": "bb"}) is not None
    assert svc.filter_event("node_seen", {}) is None


def test_filter_does_not_mutate_the_shared_event():
    svc = EventWebhookService(make_bot())
    data = {"is_dm": True, "text": "keep me"}
    svc.filter_event("message_received", data)
    assert data["text"] == "keep me"


# -- request building -------------------------------------------------------

def test_request_is_signed_when_secret_set():
    svc = EventWebhookService(make_bot(secret="k3y"))
    body, headers = svc.build_request({"event": "command_run", "data": {"command": "ping"}})
    expected = hmac.new(b"k3y", body, hashlib.sha256).hexdigest()
    assert headers["X-MeshCore-Signature"] == f"sha256={expected}"
    assert headers["X-MeshCore-Event"] == "command_run"
    assert json.loads(body)["data"] == {"command": "ping"}


def test_request_unsigned_without_secret():
    _, headers = EventWebhookService(make_bot()).build_request({"event": "x"})
    assert "X-MeshCore-Signature" not in headers


# -- delivery ---------------------------------------------------------------

async def test_end_to_end_event_reaches_every_url():
    bot = make_bot(urls="https://a.example/h, https://b.example/h")
    svc = EventWebhookService(bot)
    session = FakeSession()
    await svc.start()
    await svc._session.close()
    svc._session = session

    mesh_events.emit(bot, "message_received", lambda: {"channel": "general", "text": "hello", "is_dm": False})
    await asyncio.wait_for(svc._queue.join(), timeout=2)

    assert [p["url"] for p in session.posts] == ["https://a.example/h", "https://b.example/h"]
    envelope = json.loads(session.posts[0]["body"])
    assert envelope["event"] == "message_received"
    assert envelope["bot"] == "TestBot"
    assert envelope["data"]["text"] == "hello"
    assert session.posts[0]["allow_redirects"] is False
    assert svc.sent == 2

    await svc.stop()
    assert session.closed is True
    assert not bot.mesh_events.has_listeners


async def test_unselected_events_are_not_sent():
    bot = make_bot(events="command_run")
    svc = EventWebhookService(bot)
    await svc.start()
    mesh_events.emit(bot, "message_received", lambda: {"text": "x"})
    assert svc._queue.qsize() == 0
    await svc.stop()


async def test_retries_once_on_server_error_then_succeeds():
    svc = EventWebhookService(make_bot())
    svc._session = FakeSession([503, 200])
    await svc.deliver({"event": "command_run", "data": {}})
    assert len(svc._session.posts) == 2
    assert svc.sent == 1 and svc.failed == 0


async def test_retries_once_on_network_error_then_gives_up():
    svc = EventWebhookService(make_bot())
    svc._session = FakeSession([OSError("refused"), OSError("refused")])
    await svc.deliver({"event": "command_run", "data": {}})
    assert len(svc._session.posts) == 2
    assert svc.failed == 1


async def test_client_error_is_not_retried():
    svc = EventWebhookService(make_bot())
    svc._session = FakeSession([401])
    await svc.deliver({"event": "command_run", "data": {}})
    assert len(svc._session.posts) == 1
    assert svc.failed == 1


async def test_full_queue_drops_oldest():
    svc = EventWebhookService(make_bot())
    svc._running = True
    svc._queue = asyncio.Queue(maxsize=2)
    for n in range(3):
        svc.on_event("command_run", {"n": n})
    kept = [svc._queue.get_nowait()["data"]["n"] for _ in range(2)]
    assert kept == [1, 2]
    assert svc.dropped == 1


# -- event bus --------------------------------------------------------------

def test_emit_is_free_and_silent_without_listeners():
    bot = SimpleNamespace(logger=logging.getLogger("t"))
    called = []
    mesh_events.emit(bot, "node_seen", lambda: called.append(1) or {})
    assert called == []


def test_listener_errors_never_reach_the_emitter():
    bot = SimpleNamespace(logger=logging.getLogger("t"))
    bus = mesh_events.get_event_bus(bot)
    seen = []
    bus.subscribe(lambda e, d: 1 / 0)
    bus.subscribe(lambda e, d: seen.append((e, d)))
    mesh_events.emit(bot, "node_seen", lambda: {"public_key": "aa"})
    assert seen == [("node_seen", {"public_key": "aa"})]


def test_payload_builder_errors_are_swallowed():
    bot = SimpleNamespace(logger=logging.getLogger("t"))
    mesh_events.get_event_bus(bot).subscribe(lambda e, d: None)
    mesh_events.emit(bot, "node_seen", lambda: 1 / 0)


async def test_async_listeners_run_in_the_background():
    bot = SimpleNamespace(logger=logging.getLogger("t"))
    done = asyncio.Event()

    async def listener(event, data):
        done.set()

    mesh_events.get_event_bus(bot).subscribe(listener)
    mesh_events.emit(bot, "command_run", lambda: {})
    await asyncio.wait_for(done.wait(), timeout=1)


def test_async_listener_without_loop_does_not_leak():
    bot = SimpleNamespace(logger=logging.getLogger("t"))

    async def listener(event, data):
        return None

    mesh_events.get_event_bus(bot).subscribe(listener)
    mesh_events.emit(bot, "command_run", lambda: {})
