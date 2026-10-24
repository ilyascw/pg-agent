"""Runs a turn and reports its tool calls as they happen, independent of Telegram."""

from __future__ import annotations

import asyncio
import contextlib
from collections.abc import Awaitable, Callable, Iterator
from uuid import UUID

from pg_agent import AgentClient, Event

from .render import Status


class Feed:
    """Routes events from the client's single listener to the turn waiting on that stream."""

    def __init__(self, client: AgentClient) -> None:
        self.client = client
        self.queues: dict[UUID, asyncio.Queue[Event]] = {}

    async def run(self) -> None:
        async for event in self.client.follow():
            queue = self.queues.get(event.stream_id)
            if queue is not None:
                queue.put_nowait(event)

    @contextlib.contextmanager
    def subscribe(self, stream: UUID) -> Iterator[asyncio.Queue[Event]]:
        queue: asyncio.Queue[Event] = asyncio.Queue()
        self.queues[stream] = queue
        try:
            yield queue
        finally:
            del self.queues[stream]


async def run_turn(
    client: AgentClient,
    feed: Feed,
    stream: UUID,
    text: str,
    on_status: Callable[[str], Awaitable[None]],
) -> str | None:
    """Run one turn; on_status gets the tool call list each time it changes."""
    status = Status()

    async def watch(events: asyncio.Queue[Event]) -> None:
        while True:
            if status.apply(await events.get()):
                await on_status(status.text())

    with feed.subscribe(stream) as events:
        watcher = asyncio.create_task(watch(events))
        try:
            return await client.run(stream, text)
        finally:
            watcher.cancel()
