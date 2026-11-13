#!/usr/bin/env python3
"""
Nearby command for the MeshCore Bot
Actively tests which repeaters are in direct radio range and lists them by signal
"""

import asyncio
from typing import Any, Optional

from ..models import MeshMessage
from ..nearby_repeaters import (
    REASON_BUSY,
    REASON_COOLDOWN,
    REASON_NOT_CONNECTED,
    format_reply,
    get_probe,
    repeaters_from_result,
)
from .base_command import BaseCommand


class NearbyCommand(BaseCommand):
    """Runs one nearby repeater test and replies with who answered.

    The test listens for ``[Nearby_Command] listen_seconds`` (15 by default), so
    the command acknowledges straight away and sends the list in a second
    message rather than holding the reply open. The node-wide gap between tests
    (``min_gap_seconds``) belongs to the shared probe, so the dashboard button
    and this command ration the same airtime.
    """

    name = "nearby"
    keywords = ['nearby', 'rptest']
    description = "Tests which repeaters hear this node directly, listed by signal"
    cooldown_seconds = 120
    category = "special"

    def __init__(self, bot: Any):
        super().__init__(bot)
        self.command_enabled = self.get_config_value(
            'Nearby_Command', 'enabled', fallback=True, value_type='bool'
        )
        self._task: Optional[asyncio.Task] = None

    def get_help_text(self) -> str:
        return self.translate('commands.nearby.description')

    def can_execute(self, message: MeshMessage, skip_channel_check: bool = False) -> bool:
        if not self.command_enabled:
            return False
        return super().can_execute(message, skip_channel_check=skip_channel_check)

    async def execute(self, message: MeshMessage) -> bool:
        probe = get_probe(self.bot)
        refused = probe.refusal()
        if refused is not None:
            await self.send_response(message, self._refusal_text(refused))
            return True
        if self._task is not None and not self._task.done():
            await self.send_response(message, self.translate('commands.nearby.busy'))
            return True

        await self.send_response(
            message,
            self.translate('commands.nearby.started', seconds=int(probe.listen_seconds)),
        )
        self._task = asyncio.create_task(self._run_and_report(message))
        return True

    async def _run_and_report(self, message: MeshMessage) -> None:
        probe = get_probe(self.bot)
        result = await probe.run()
        await self.send_response(
            message, self.format_result(message, result), skip_user_rate_limit=True
        )

    def _refusal_text(self, result: dict[str, Any]) -> str:
        reason = result.get('reason')
        if reason == REASON_BUSY:
            return self.translate('commands.nearby.busy')
        if reason == REASON_COOLDOWN:
            return self.translate('commands.nearby.cooldown',
                                  seconds=int(result.get('retry_after') or 0))
        if reason == REASON_NOT_CONNECTED:
            return self.translate('commands.nearby.not_connected')
        return self.translate('commands.nearby.failed',
                              reason=result.get('error') or reason or 'unknown error')

    def format_result(self, message: MeshMessage, result: dict[str, Any]) -> str:
        """Render a probe result as one mesh-sized reply."""
        if not result.get('ok'):
            return self._refusal_text(result)
        repeaters = repeaters_from_result(result)
        if not repeaters:
            return self.translate('commands.nearby.none',
                                  seconds=int(result.get('listened') or 0))
        return format_reply(
            repeaters,
            self.get_max_message_length(message),
            header=self.translate('commands.nearby.header'),
        )
