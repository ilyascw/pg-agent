import asyncio

from textual.widgets import Input, Markdown, Static

from pg_agent import AgentClient
from pg_agent_tui.app import AgentApp

from .conftest import DSN


async def wait_for(condition, timeout: float = 5) -> None:
    async with asyncio.timeout(timeout):
        while not condition():
            await asyncio.sleep(0.05)


async def test_chat_turn_renders_calls_and_answer(client: AgentClient) -> None:
    app = AgentApp(DSN, "tester")
    async with app.run_test() as pilot:
        await pilot.click("Input")
        await pilot.press(*"say ping", "enter")
        await wait_for(lambda: app.query(Markdown))

        lines = [str(w.render()) for w in app.query("#log > Static")]
        assert lines == ["› say ping", '→ echo(text="ping")', "← echo: echo: ping"]
        assert app.query_one(Markdown).source == "pong"
        assert "сессия" in str(app.query_one("#status", Static).render())


async def test_slash_shows_command_hints(client: AgentClient) -> None:
    app = AgentApp(DSN, "tester")
    async with app.run_test() as pilot:
        hints = app.query_one("#hints", Static)
        await pilot.click("Input")
        await pilot.press("/")
        assert hints.has_class("visible")
        assert "/sessions" in str(hints.render())

        await pilot.press("r", "e", "right")
        assert app.query_one(Input).value == "/resume"
        assert str(hints.render()).startswith("/resume ID")

        await pilot.press(
            "backspace",
            "backspace",
            "backspace",
            "backspace",
            "backspace",
            "backspace",
            "backspace",
        )
        assert not hints.has_class("visible")
