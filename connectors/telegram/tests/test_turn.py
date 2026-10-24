import asyncio

import psycopg
from pg_agent import AgentClient

from pg_agent_telegram.chats import Chats
from pg_agent_telegram.turn import Feed, run_turn


async def test_turn_reports_tool_calls(client: AgentClient) -> None:
    feed = Feed(client)
    feed_task = asyncio.create_task(feed.run())
    statuses: list[str] = []

    async def show(text: str) -> None:
        statuses.append(text)

    try:
        stream = await client.open()
        assert await run_turn(client, feed, stream, "say ping", show) == "pong"
    finally:
        feed_task.cancel()

    assert statuses == ['⏳ echo(text="ping")', '✅ echo(text="ping")']
    assert feed.queues == {}


async def test_chat_keeps_its_session(client: AgentClient, conn: psycopg.AsyncConnection) -> None:
    chats = Chats(client, conn)
    first = await chats.stream(42)
    assert await chats.stream(42) == first

    fresh = await chats.start_new(42)
    assert fresh != first
    assert await chats.stream(42) == fresh

    await chats.switch(42, first)
    assert await chats.stream(42) == first
    assert await chats.stream(43) != first
