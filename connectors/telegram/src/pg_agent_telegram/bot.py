"""Telegram handlers: thin glue between aiogram, the chat map and run_turn."""

from __future__ import annotations

import contextlib
import html
from collections.abc import Awaitable, Callable
from typing import Any

import psycopg
from aiogram import Bot, Dispatcher, F
from aiogram.exceptions import TelegramAPIError
from aiogram.filters import Command, CommandObject, CommandStart
from aiogram.types import BotCommand, Message, MessageEntity, TelegramObject
from aiogram.utils.chat_action import ChatActionSender
from pg_agent import AgentClient

from .chats import Chats
from .render import answer_parts
from .turn import Feed, run_turn

# One list drives the bot menu in Telegram and /help.
COMMANDS = (
    BotCommand(command="new", description="новая сессия"),
    BotCommand(command="sessions", description="последние сессии"),
    BotCommand(command="resume", description="продолжить сессию: /resume ID"),
    BotCommand(command="tools", description="инструменты агента"),
    BotCommand(command="help", description="справка"),
)

HELP = "Пиши сообщения, я отвечу. Команды:\n" + "\n".join(
    f"/{c.command} — {c.description}" for c in COMMANDS
)

Handler = Callable[[TelegramObject, dict[str, Any]], Awaitable[Any]]


def build_dispatcher(
    client: AgentClient, chats: Chats, feed: Feed, allowed: frozenset[int]
) -> Dispatcher:
    dp = Dispatcher()

    @dp.message.outer_middleware()
    async def only_allowed(handler: Handler, message: Message, data: dict[str, Any]) -> Any:
        # The agent sees notes and tasks of its owner, so strangers get only their id.
        user = message.from_user
        if user is None or user.id not in allowed:
            await message.answer(
                f"Нет доступа. Твой id: <code>{user.id if user else '?'}</code>",
                parse_mode="HTML",
            )
            return None
        return await handler(message, data)

    @dp.message(CommandStart())
    @dp.message(Command("help"))
    async def on_help(message: Message) -> None:
        await message.answer(HELP)

    @dp.message(Command("new"))
    async def on_new(message: Message) -> None:
        stream = await chats.start_new(message.chat.id)
        await message.answer(f"Новая сессия <code>{str(stream)[:8]}</code>", parse_mode="HTML")

    @dp.message(Command("sessions"))
    async def on_sessions(message: Message) -> None:
        streams = await client.streams(10)
        if not streams:
            await message.answer("Сессий пока нет.")
            return
        lines = [
            f"<code>{str(s.id)[:8]}</code> {s.created_at:%d.%m %H:%M} {html.escape(s.title or '—')}"
            for s in streams
        ]
        await message.answer("\n".join(lines) + "\n\nПродолжить: /resume ID", parse_mode="HTML")

    @dp.message(Command("resume"))
    async def on_resume(message: Message, command: CommandObject) -> None:
        if not command.args:
            await message.answer("Укажи начало ID: /resume a1b2c3d4")
            return
        try:
            stream = await client.resolve(command.args.strip())
        except LookupError as error:
            await message.answer(str(error))
            return
        await chats.switch(message.chat.id, stream)
        await message.answer(f"Продолжаем сессию <code>{str(stream)[:8]}</code>", parse_mode="HTML")

    @dp.message(Command("tools"))
    async def on_tools(message: Message) -> None:
        info = await client.info()
        names = sorted(tool["name"] for tool in info.tools)
        await message.answer(f"{info.model}, инструментов: {len(names)}\n\n" + "\n".join(names))

    @dp.message(F.text)
    async def on_text(message: Message, bot: Bot) -> None:
        assert message.text is not None
        chat_id = message.chat.id
        async with chats.locks[chat_id]:
            stream = await chats.stream(chat_id)
            status: Message | None = None

            async def show(text: str) -> None:
                # Progress is cosmetic: a failed edit must not break the turn.
                nonlocal status
                with contextlib.suppress(TelegramAPIError):
                    if status is None:
                        status = await message.answer(text)
                    else:
                        await status.edit_text(text)

            try:
                async with ChatActionSender.typing(bot=bot, chat_id=chat_id):
                    answer = await run_turn(client, feed, stream, message.text, show)
            except psycopg.Error as error:
                reason = error.diag.message_primary or str(error)
                await message.answer(f"⚠️ {reason}")
                return

        for text, entities in answer_parts(answer or "…"):
            await message.answer(text, entities=[MessageEntity(**entity) for entity in entities])

    @dp.message()
    async def on_other(message: Message) -> None:
        await message.answer("Пока понимаю только текст.")

    return dp
