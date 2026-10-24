import asyncio

import pytest

from pg_agent import AgentClient, Event


async def test_turn_events_arrive_live(client: AgentClient) -> None:
    stream = await client.open()
    seen: list[Event] = []

    async def collect() -> None:
        async for event in client.follow():
            if event.stream_id == stream:
                seen.append(event)
                if event.kind == "model" and not event.payload["tool_calls"]:
                    return

    follower = asyncio.create_task(collect())
    assert await client.run(stream, "say ping") == "pong"
    await asyncio.wait_for(follower, timeout=5)

    assert [e.kind for e in seen] == ["user", "model", "tool_result", "model"]
    assert seen == await client.history(stream)


async def test_streams_and_resolve(client: AgentClient) -> None:
    stream = await client.open()
    await client.run(stream, "say ping")

    assert (await client.streams())[0].title == "say ping"
    assert await client.resolve(stream.hex[:8]) == stream
    with pytest.raises(LookupError):
        await client.resolve("zzzz")


async def test_info_lists_tools(client: AgentClient) -> None:
    info = await client.info()
    assert (info.model, [t["name"] for t in info.tools]) == ("fake-model", ["echo", "fail"])
