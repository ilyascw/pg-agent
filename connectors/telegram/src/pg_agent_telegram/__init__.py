"""Telegram bot connector for pg-agent."""

import asyncio
import logging
import os
import sys

import psycopg
from aiogram import Bot
from aiogram.client.default import DefaultBotProperties
from pg_agent import AgentClient

from .bot import COMMANDS, build_dispatcher
from .chats import Chats
from .turn import Feed

DEFAULT_DSN = "postgresql://agent:agent@localhost:5433/agent"


async def serve(token: str, dsn: str, agent: str, allowed: frozenset[int]) -> None:
    bot = Bot(token, default=DefaultBotProperties(link_preview_is_disabled=True))
    async with (
        AgentClient(dsn, agent) as client,
        await psycopg.AsyncConnection.connect(dsn, autocommit=True) as conn,
    ):
        await client.info()  # fails fast when the agent is not installed
        feed = Feed(client)
        dp = build_dispatcher(client, Chats(client, conn), feed, allowed)
        await bot.set_my_commands(list(COMMANDS))
        feed_task = asyncio.create_task(feed.run())
        try:
            await dp.start_polling(bot)
        finally:
            feed_task.cancel()
            await bot.session.close()


def main() -> None:
    token = os.environ.get("TELEGRAM_BOT_TOKEN", "")
    allowed = frozenset(
        int(user) for user in os.environ.get("TELEGRAM_ALLOWED_USERS", "").split(",") if user
    )
    if not token or not allowed:
        sys.exit("Set TELEGRAM_BOT_TOKEN and TELEGRAM_ALLOWED_USERS in .env")
    logging.basicConfig(level=logging.INFO)
    asyncio.run(
        serve(
            token,
            os.environ.get("PG_AGENT_DSN", DEFAULT_DSN),
            os.environ.get("PG_AGENT_NAME", "personal"),
            allowed,
        )
    )
