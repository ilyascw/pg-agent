"""Async client for the pg-agent core contract.

The core is driven only through these calls:

- ``runtime.open(agent)`` starts a stream;
- ``CALL runtime.run(stream, text, null)`` runs one turn, committing every step;
- ``LISTEN agent_events`` reports every committed event;
- ``core.event`` / ``core.streams`` / ``tools.schemas`` read state.

A turn and the event feed use separate connections: the turn blocks its connection
until the model answers, while events keep arriving on the listener.
"""

from __future__ import annotations

import json
from collections.abc import AsyncIterator
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Self
from uuid import UUID

import psycopg
from psycopg.rows import dict_row
from tzlocal import get_localzone_name

CHANNEL = "agent_events"


@dataclass(frozen=True, slots=True)
class Event:
    id: int
    stream_id: UUID
    kind: str
    payload: dict[str, Any]


@dataclass(frozen=True, slots=True)
class StreamInfo:
    id: UUID
    created_at: datetime
    title: str | None
    events: int


@dataclass(frozen=True, slots=True)
class AgentInfo:
    name: str
    model: str
    tools: list[dict[str, Any]]


class AgentClient:
    """One agent in one database, as seen by a connector."""

    def __init__(self, dsn: str, agent: str) -> None:
        self.dsn = dsn
        self.agent = agent
        self._query: psycopg.AsyncConnection[dict[str, Any]] | None = None
        self._turn: psycopg.AsyncConnection[dict[str, Any]] | None = None
        self._listen: psycopg.AsyncConnection[dict[str, Any]] | None = None

    async def __aenter__(self) -> Self:
        self._query = await self._connect()
        self._turn = await self._connect()
        self._listen = await self._connect()
        await self._listen.execute(f"listen {CHANNEL}")
        return self

    async def __aexit__(self, *exc: object) -> None:
        for conn in (self._query, self._turn, self._listen):
            if conn is not None:
                await conn.close()

    async def _connect(self) -> psycopg.AsyncConnection[dict[str, Any]]:
        # Autocommit: runtime.run manages its own transactions. The session time zone
        # makes tools report the user's local time.
        return await psycopg.AsyncConnection.connect(
            self.dsn,
            autocommit=True,
            row_factory=dict_row,
            options=f"-c TimeZone={get_localzone_name()}",
        )

    @staticmethod
    def _require(
        conn: psycopg.AsyncConnection[dict[str, Any]] | None,
    ) -> psycopg.AsyncConnection[dict[str, Any]]:
        if conn is None:
            raise RuntimeError("AgentClient is not connected; use 'async with'")
        return conn

    async def info(self) -> AgentInfo:
        conn = self._require(self._query)
        cursor = await conn.execute(
            "select a.name, a.model, tools.schemas(a.name) as tools"
            " from runtime.agent as a where a.name = %s",
            (self.agent,),
        )
        row = await cursor.fetchone()
        if row is None:
            raise LookupError(f"agent {self.agent!r} is not installed")
        return AgentInfo(name=row["name"], model=row["model"], tools=row["tools"])

    async def open(self) -> UUID:
        conn = self._require(self._query)
        cursor = await conn.execute("select runtime.open(%s) as id", (self.agent,))
        row = await cursor.fetchone()
        assert row is not None
        return row["id"]

    async def run(self, stream: UUID, text: str) -> str | None:
        """Run one turn; its events arrive through :meth:`follow` while it runs."""
        conn = self._require(self._turn)
        cursor = await conn.execute("call runtime.run(%s, %s, null)", (stream, text))
        row = await cursor.fetchone()
        return None if row is None else row["p_answer"]

    async def history(self, stream: UUID) -> list[Event]:
        conn = self._require(self._query)
        cursor = await conn.execute(
            "select id, stream_id, kind, payload from core.event where stream_id = %s order by id",
            (stream,),
        )
        return [Event(**row) for row in await cursor.fetchall()]

    async def streams(self, limit: int = 20) -> list[StreamInfo]:
        conn = self._require(self._query)
        cursor = await conn.execute("select * from core.streams(%s, %s)", (self.agent, limit))
        return [StreamInfo(**row) for row in await cursor.fetchall()]

    async def resolve(self, prefix: str) -> UUID:
        """Find this agent's stream by a unique prefix of its id."""
        conn = self._require(self._query)
        cursor = await conn.execute(
            "select id from core.stream where agent = %s and id::text like %s limit 2",
            (self.agent, prefix.lower() + "%"),
        )
        rows = await cursor.fetchall()
        if len(rows) != 1:
            raise LookupError(
                f"no session starts with {prefix!r}"
                if not rows
                else f"{prefix!r} matches several sessions"
            )
        return rows[0]["id"]

    async def follow(self) -> AsyncIterator[Event]:
        """Every event committed to any stream of the database, in commit order."""
        listen = self._require(self._listen)
        query = self._require(self._query)
        async for notify in listen.notifies():
            event_id = json.loads(notify.payload)["event_id"]
            cursor = await query.execute(
                "select id, stream_id, kind, payload from core.event where id = %s",
                (event_id,),
            )
            row = await cursor.fetchone()
            if row is not None:
                yield Event(**row)
