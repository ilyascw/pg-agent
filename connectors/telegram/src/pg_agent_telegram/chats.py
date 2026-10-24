"""Which session each chat talks in, kept in telegram.chat so it survives restarts."""

from __future__ import annotations

import asyncio
from collections import defaultdict
from typing import Any
from uuid import UUID

import psycopg
from pg_agent import AgentClient


class Chats:
    def __init__(self, client: AgentClient, conn: psycopg.AsyncConnection[Any]) -> None:
        self.client = client
        self.conn = conn
        # One turn per chat at a time: a second message waits for the first answer.
        self.locks: defaultdict[int, asyncio.Lock] = defaultdict(asyncio.Lock)

    async def stream(self, chat_id: int) -> UUID:
        """The chat's current session; a new one on the first message."""
        cursor = await self.conn.execute(
            "select stream_id from telegram.chat where chat_id = %s and agent = %s",
            (chat_id, self.client.agent),
        )
        row = await cursor.fetchone()
        return row[0] if row else await self.start_new(chat_id)

    async def start_new(self, chat_id: int) -> UUID:
        stream = await self.client.open()
        await self.switch(chat_id, stream)
        return stream

    async def switch(self, chat_id: int, stream: UUID) -> None:
        await self.conn.execute(
            "insert into telegram.chat (chat_id, agent, stream_id) values (%s, %s, %s)"
            " on conflict (chat_id, agent) do update set stream_id = excluded.stream_id",
            (chat_id, self.client.agent, stream),
        )
