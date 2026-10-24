"""Textual chat over AgentClient. All agent state lives in the database: the app only
sends turns and renders events it is notified about."""

from __future__ import annotations

import os
from contextlib import AsyncExitStack
from typing import ClassVar
from uuid import UUID

import psycopg
from pg_agent import AgentClient, AgentInfo, Event
from textual.app import App, ComposeResult
from textual.binding import BindingType
from textual.containers import VerticalScroll
from textual.suggester import SuggestFromList
from textual.widget import Widget
from textual.widgets import Input, Markdown, Static

from .commands import COMMANDS, describe, matching
from .render import Line, ToolCall, ToolResult, event_items, prompt_tokens
from .tool_view import ToolView

HELP = describe() + "\n\n→ дописывает подсказанную команду."


class AgentApp(App[None]):
    CSS = """
    #log { height: 1fr; padding: 0 1; }
    #log > * { margin: 1 0 0 0; }
    .user { color: $accent; text-style: bold; }
    .tool { margin: 0; }
    .error { color: $error; margin: 0; }
    .info { color: $text-muted; }
    #hints { display: none; padding: 0 1; color: $text-muted; background: $boost; }
    #hints.visible { display: block; }
    #status { height: 1; padding: 0 1; background: $panel; color: $text-muted; }
    """
    BINDINGS: ClassVar[list[BindingType]] = [
        ("ctrl+n", "new_session", "Новая сессия"),
        ("ctrl+q", "quit", "Выход"),
    ]

    def __init__(self, dsn: str, agent: str) -> None:
        super().__init__()
        self.client = AgentClient(dsn, agent)
        self.context_window = int(os.environ.get("PG_AGENT_CONTEXT_WINDOW", "0")) or None
        self._resources = AsyncExitStack()
        self._agent: AgentInfo | None = None
        self._stream: UUID | None = None
        self._last_event = 0
        self._tokens: int | None = None
        self._busy = False
        self._calls: dict[str, ToolView] = {}

    def compose(self) -> ComposeResult:
        yield VerticalScroll(id="log")
        yield Static(id="hints", markup=False)
        yield Static(id="status", markup=False)
        yield Input(
            placeholder="Сообщение или / для команд",
            suggester=SuggestFromList([c.name for c in COMMANDS], case_sensitive=False),
        )

    async def on_mount(self) -> None:
        try:
            await self._resources.enter_async_context(self.client)
            self._agent = await self.client.info()
        except (psycopg.Error, LookupError) as exc:
            self.exit(message=f"pg-agent: {exc}")
            return
        self.run_worker(self._follow(), name="follow")
        self._render_status()

    async def on_unmount(self) -> None:
        await self._resources.aclose()

    async def _follow(self) -> None:
        async for event in self.client.follow():
            if event.stream_id == self._stream:
                await self._show(event)

    def on_input_changed(self, message: Input.Changed) -> None:
        commands = matching(message.value)
        hints = self.query_one("#hints", Static)
        hints.set_class(bool(commands), "visible")
        if commands:
            hints.update(describe(commands))

    async def on_input_submitted(self, message: Input.Submitted) -> None:
        text = message.value.strip()
        message.input.value = ""
        if not text:
            return
        if text.startswith("/"):
            await self._command(text)
        elif self._busy:
            self.notify("Агент ещё отвечает", severity="warning")
        else:
            if self._stream is None:
                self._stream = await self.client.open()
            self._busy = True
            self._render_status()
            self.run_worker(self._turn(self._stream, text), name="turn")

    async def _turn(self, stream: UUID, text: str) -> None:
        try:
            await self.client.run(stream, text)
        except psycopg.Error as exc:
            await self._mount(Line("error", exc.diag.message_primary or str(exc)))
        finally:
            self._busy = False
            self._render_status()

    async def _command(self, text: str) -> None:
        name, _, argument = text.partition(" ")
        match name:
            case "/help":
                await self._info(HELP)
            case "/new":
                await self.action_new_session()
            case "/sessions":
                streams = await self.client.streams()
                await self._info(
                    "\n".join(
                        f"{s.id.hex[:8]}  {s.created_at:%Y-%m-%d %H:%M}  {s.title or '—'}"
                        for s in streams
                    )
                    or "Сессий нет."
                )
            case "/resume" if argument:
                await self._resume(argument.strip())
            case "/tools":
                tools = self._agent.tools if self._agent else []
                await self._info("\n".join(f"{t['name']} — {t['description']}" for t in tools))
            case "/quit":
                self.exit()
            case _:
                await self._info(f"Неизвестная команда {text}.\n\n{HELP}")

    async def action_new_session(self) -> None:
        if self._busy:
            self.notify("Агент ещё отвечает", severity="warning")
            return
        self._stream = None
        self._last_event = 0
        self._tokens = None
        self._calls.clear()
        await self.query_one("#log").remove_children()
        self._render_status()

    async def _resume(self, prefix: str) -> None:
        if self._busy:
            self.notify("Агент ещё отвечает", severity="warning")
            return
        try:
            stream = await self.client.resolve(prefix)
        except LookupError as exc:
            await self._info(str(exc))
            return
        await self.action_new_session()
        self._stream = stream
        for event in await self.client.history(stream):
            await self._show(event)
        self._render_status()

    async def _show(self, event: Event) -> None:
        # History and notifications can overlap right after /resume.
        if event.id <= self._last_event:
            return
        self._last_event = event.id
        self._tokens = prompt_tokens(event) or self._tokens
        for item in event_items(event):
            match item:
                case ToolCall():
                    view = ToolView(item)
                    self._calls[item.id] = view
                    await self._mount_widget(view)
                case ToolResult():
                    if view := self._calls.pop(item.call_id, None):
                        view.finish(item)
                    else:
                        view = ToolView(ToolCall(item.call_id, item.name, ""))
                        await self._mount_widget(view)
                        view.finish(item)
                case Line():
                    await self._mount(item)
        self._render_status()

    async def _mount(self, line: Line) -> None:
        widget: Widget = (
            Markdown(line.text)
            if line.kind == "answer"
            else Static(_prefix(line) + line.text, markup=False, classes=line.kind)
        )
        await self._mount_widget(widget)

    async def _mount_widget(self, widget: Widget) -> None:
        log = self.query_one("#log", VerticalScroll)
        await log.mount(widget)
        log.scroll_end(animate=False)

    async def _info(self, text: str) -> None:
        log = self.query_one("#log", VerticalScroll)
        await log.mount(Static(text, markup=False, classes="info"))
        log.scroll_end(animate=False)

    def _render_status(self) -> None:
        parts = []
        if self._agent:
            parts.append(f"{self._agent.name} · {self._agent.model}")
        parts.append(f"сессия {self._stream.hex[:8]}" if self._stream else "новая сессия")
        if self._tokens is not None:
            parts.append(
                f"контекст {self._tokens / self.context_window:.0%}"
                if self.context_window
                else f"контекст {self._tokens} ток."
            )
        if self._busy:
            parts.append("думаю…")
        self.query_one("#status", Static).update(" · ".join(parts))


def _prefix(line: Line) -> str:
    return {"user": "› ", "error": "✗ "}.get(line.kind, "")
