"""Tests for the nearby repeater test (modules/nearby_repeaters.py)."""

from __future__ import annotations

import asyncio
import configparser
import logging
import types

import pytest

from modules import nearby_repeaters as nr
from modules.neighbors_discovery import NeighborEntry

KEY_A = "a1" * 32
KEY_B = "b2" * 32
KEY_C = "c3" * 32


def make_bot(*, connected=True, contacts=None, config=None, capture=None):
    meshcore = types.SimpleNamespace(
        contacts=contacts if contacts is not None else {},
        self_info={"public_key": "ff" * 32},
    )
    cfg = config or configparser.ConfigParser()
    return types.SimpleNamespace(
        logger=logging.getLogger("test-nearby"),
        config=cfg,
        meshcore=meshcore,
        connected=connected,
        db_manager=None,
        packet_capture_service=capture,
    )


@pytest.fixture
def fake_discover(monkeypatch):
    """Replace the radio round-trip; records what the probe asked for."""
    calls = []
    state = {"entries": [], "hang": False}

    async def discover(meshcore, cfg, self_pubkey, logger, *, debug=False, still_valid=None):
        calls.append({"meshcore": meshcore, "cfg": cfg, "self": self_pubkey,
                      "still_valid": still_valid})
        if state["hang"]:
            await asyncio.sleep(5)
        if state["entries"] is None:
            return None
        return [NeighborEntry(pubkey=k, snr=s, heard_at=0.0) for k, s in state["entries"]]

    monkeypatch.setattr(nr, "discover_neighbors", discover)
    return types.SimpleNamespace(calls=calls, state=state)


# -- clamps -----------------------------------------------------------------

@pytest.mark.parametrize("raw,expected", [
    (15, 15.0), (1, 5.0), (600, 60.0), ("x", nr.DEFAULT_LISTEN_SECONDS),
    (float("nan"), nr.DEFAULT_LISTEN_SECONDS),
])
def test_listen_seconds_is_clamped(raw, expected):
    assert nr.clamp_listen_seconds(raw) == expected


@pytest.mark.parametrize("raw,expected", [
    (300, 300.0), (0, 30.0), (-5, 30.0), (None, nr.DEFAULT_MIN_GAP_SECONDS),
])
def test_min_gap_has_a_floor(raw, expected):
    assert nr.clamp_min_gap_seconds(raw) == expected


def test_config_values_are_read_and_clamped():
    cfg = configparser.ConfigParser()
    cfg.add_section("Nearby_Command")
    cfg.set("Nearby_Command", "listen_seconds", "200")
    cfg.set("Nearby_Command", "min_gap_seconds", "5")
    probe = nr.NearbyRepeaterProbe(make_bot(config=cfg))
    assert probe.listen_seconds == 60.0
    assert probe.min_gap_seconds == 30.0


# -- formatting -------------------------------------------------------------

def test_format_reply_lists_name_prefix_and_snr():
    reps = [nr.NearbyRepeater(KEY_A, "Hilltop", 9.5), nr.NearbyRepeater(KEY_B, "Valley", -3.25)]
    assert nr.format_reply(reps, 160) == "Nearby repeaters (2): Hilltop a1 +9.5dB, Valley b2 -3.2dB"


def test_format_reply_summarises_what_does_not_fit():
    reps = [nr.NearbyRepeater(f"{i:02x}" * 32, f"Repeater-{i:02d}", 5.0) for i in range(20)]
    text = nr.format_reply(reps, 120)
    assert len(text.encode("utf-8")) <= 120
    assert text.startswith("Nearby repeaters (20): Repeater-00")
    assert text.endswith("more")


def test_format_reply_respects_tiny_budget():
    reps = [nr.NearbyRepeater(KEY_A, "A very long repeater name indeed", 1.0)]
    assert len(nr.format_reply(reps, 20).encode("utf-8")) <= 20


def test_format_reply_empty():
    assert nr.format_reply([], 160) == ""


def test_resolve_name_uses_contacts_then_prefix():
    bot = make_bot()
    mc = types.SimpleNamespace(contacts={KEY_A: {"adv_name": "Hill\nTop"}})
    assert "\n" not in nr.resolve_name(bot, mc, KEY_A)
    assert nr.resolve_name(bot, mc, KEY_A).startswith("Hill")
    assert nr.resolve_name(bot, mc, KEY_B) == KEY_B[:8]


def test_resolve_name_falls_back_to_tracking_table():
    bot = make_bot()
    bot.db_manager = types.SimpleNamespace(
        execute_query=lambda q, p: [{"name": "Tracked"}] if p == (KEY_C,) else []
    )
    assert nr.resolve_name(bot, types.SimpleNamespace(contacts={}), KEY_C) == "Tracked"


# -- run --------------------------------------------------------------------

async def test_run_lists_responders_strongest_first(fake_discover):
    fake_discover.state["entries"] = [(KEY_B, -2.0), (KEY_A, 7.5)]
    bot = make_bot(contacts={KEY_A: {"adv_name": "Hilltop"}})
    probe = nr.NearbyRepeaterProbe(bot)

    result = await probe.run()

    assert result["ok"] is True
    assert result["count"] == 2
    assert [r["name"] for r in result["repeaters"]] == ["Hilltop", KEY_B[:8]]
    assert result["repeaters"][0] == {"pubkey": KEY_A, "prefix": "a1", "name": "Hilltop", "snr": 7.5}
    call = fake_discover.calls[0]
    assert call["cfg"].discover_window == nr.DEFAULT_LISTEN_SECONDS
    assert call["self"] == "ff" * 32
    assert call["still_valid"]() is True
    bot.connected = False
    assert call["still_valid"]() is False


async def test_run_with_no_answers_is_ok_and_empty(fake_discover):
    probe = nr.NearbyRepeaterProbe(make_bot())
    result = await probe.run()
    assert result["ok"] is True and result["repeaters"] == []


async def test_send_failure_is_reported(fake_discover):
    fake_discover.state["entries"] = None
    result = await nr.NearbyRepeaterProbe(make_bot()).run()
    assert result["ok"] is False
    assert result["reason"] == nr.REASON_SEND_FAILED


async def test_refuses_when_not_connected(fake_discover):
    result = await nr.NearbyRepeaterProbe(make_bot(connected=False)).run()
    assert result["reason"] == nr.REASON_NOT_CONNECTED
    assert fake_discover.calls == []


async def test_second_run_inside_gap_is_refused(fake_discover):
    probe = nr.NearbyRepeaterProbe(make_bot())
    assert (await probe.run())["ok"] is True
    again = await probe.run()
    assert again["reason"] == nr.REASON_COOLDOWN
    assert 0 < again["retry_after"] <= nr.DEFAULT_MIN_GAP_SECONDS + 1
    assert len(fake_discover.calls) == 1


async def test_runs_again_after_gap(fake_discover):
    probe = nr.NearbyRepeaterProbe(make_bot())
    await probe.run()
    probe.last_run_at -= nr.DEFAULT_MIN_GAP_SECONDS + 1
    assert (await probe.run())["ok"] is True
    assert len(fake_discover.calls) == 2


async def test_concurrent_run_is_refused_as_busy(fake_discover):
    fake_discover.state["hang"] = True
    probe = nr.NearbyRepeaterProbe(make_bot())
    first = asyncio.create_task(probe.run())
    await asyncio.sleep(0)
    second = await probe.run()
    assert second["reason"] == nr.REASON_BUSY
    first.cancel()
    with pytest.raises(asyncio.CancelledError):
        await first
    assert probe.running is False


async def test_does_not_overlap_scheduled_neighbors_cycle(fake_discover):
    capture = types.SimpleNamespace(neighbors_cycle_active=True)
    result = await nr.NearbyRepeaterProbe(make_bot(capture=capture)).run()
    assert result["reason"] == nr.REASON_BUSY
    assert fake_discover.calls == []


async def test_unexpected_error_becomes_a_result(monkeypatch):
    async def boom(*a, **k):
        raise RuntimeError("radio fell over")

    monkeypatch.setattr(nr, "discover_neighbors", boom)
    probe = nr.NearbyRepeaterProbe(make_bot())
    result = await probe.run()
    assert result == {"ok": False, "reason": nr.REASON_ERROR, "repeaters": [], "count": 0,
                      "error": "radio fell over"}
    assert probe.running is False


def test_get_probe_is_shared_per_bot():
    bot = make_bot()
    assert nr.get_probe(bot) is nr.get_probe(bot)
    assert nr.get_probe(make_bot()) is not nr.get_probe(bot)


def test_repeaters_from_result_skips_bad_rows():
    rows = nr.repeaters_from_result({"repeaters": [
        {"pubkey": KEY_A, "name": "A", "snr": 1.0}, {"name": "broken"},
    ]})
    assert [r.name for r in rows] == ["A"]
