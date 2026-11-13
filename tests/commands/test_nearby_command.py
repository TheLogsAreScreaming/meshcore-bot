"""Tests for the nearby command (modules/commands/nearby_command.py)."""

from __future__ import annotations

import asyncio

import pytest

from modules import nearby_repeaters as nr
from modules.commands.nearby_command import NearbyCommand
from tests.conftest import mock_message

KEY_A = "a1" * 32


@pytest.fixture
def bot(command_mock_bot):
    command_mock_bot.connected = True
    command_mock_bot.packet_capture_service = None
    command_mock_bot.db_manager = None
    command_mock_bot.meshcore.contacts = {KEY_A: {"adv_name": "Hilltop"}}
    command_mock_bot.meshcore.self_info = {"public_key": "ff" * 32}
    command_mock_bot._nearby_repeater_probe = None
    return command_mock_bot


def sent(bot):
    return [c.args[1] for c in bot.command_manager.send_response.call_args_list]


def test_keywords_and_enable_flag(bot):
    cmd = NearbyCommand(bot)
    assert "nearby" in cmd.keywords and "rptest" in cmd.keywords
    assert cmd.can_execute(mock_message(content="nearby", is_dm=True)) is True
    bot.config.add_section("Nearby_Command")
    bot.config.set("Nearby_Command", "enabled", "false")
    assert NearbyCommand(bot).can_execute(mock_message(content="nearby", is_dm=True)) is False


async def test_acknowledges_then_reports_repeaters(bot, monkeypatch):
    async def fake_run(self):
        return {"ok": True, "reason": None, "count": 1, "listened": 15.0,
                "repeaters": [{"pubkey": KEY_A, "prefix": "a1", "name": "Hilltop", "snr": 6.0}]}

    monkeypatch.setattr(nr.NearbyRepeaterProbe, "run", fake_run)
    cmd = NearbyCommand(bot)
    msg = mock_message(content="nearby", is_dm=True)

    assert await cmd.execute(msg) is True
    await cmd._task

    replies = sent(bot)
    assert replies[0].startswith("commands.nearby.started")
    assert "Hilltop a1 +6.0dB" in replies[1]
    # The result is airtime the user already paid for; don't rate-limit it away.
    assert bot.command_manager.send_response.call_args.kwargs["skip_user_rate_limit"] is True


async def test_reports_when_nobody_answers(bot, monkeypatch):
    async def fake_run(self):
        return {"ok": True, "reason": None, "count": 0, "listened": 15.0, "repeaters": []}

    monkeypatch.setattr(nr.NearbyRepeaterProbe, "run", fake_run)
    cmd = NearbyCommand(bot)
    await cmd.execute(mock_message(content="nearby", is_dm=True))
    await cmd._task
    assert sent(bot)[-1] == "commands.nearby.none seconds=15"


async def test_refuses_immediately_when_not_connected(bot):
    bot.connected = False
    cmd = NearbyCommand(bot)
    await cmd.execute(mock_message(content="nearby", is_dm=True))
    assert cmd._task is None
    assert sent(bot) == ["commands.nearby.not_connected"]


async def test_cooldown_refusal_says_how_long(bot):
    probe = nr.get_probe(bot)
    probe.last_run_at = __import__("time").time()
    cmd = NearbyCommand(bot)
    await cmd.execute(mock_message(content="nearby", is_dm=True))
    assert sent(bot)[0].startswith("commands.nearby.cooldown seconds=")


async def test_busy_while_a_test_is_running(bot, monkeypatch):
    gate = asyncio.Event()

    async def slow_run(self):
        await gate.wait()
        return {"ok": True, "reason": None, "count": 0, "listened": 15.0, "repeaters": []}

    monkeypatch.setattr(nr.NearbyRepeaterProbe, "run", slow_run)
    cmd = NearbyCommand(bot)
    await cmd.execute(mock_message(content="nearby", is_dm=True))
    await cmd.execute(mock_message(content="nearby", is_dm=True, sender_id="Other"))
    assert "commands.nearby.busy" in sent(bot)
    gate.set()
    await cmd._task


def test_failure_text_includes_reason(bot):
    cmd = NearbyCommand(bot)
    text = cmd.format_result(mock_message(is_dm=True),
                             {"ok": False, "reason": nr.REASON_SEND_FAILED, "error": "no firmware support"})
    assert text == "commands.nearby.failed reason=no firmware support"
