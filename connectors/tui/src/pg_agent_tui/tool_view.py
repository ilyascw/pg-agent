"""One line per tool call: a spinner while it runs, then the outcome in place."""

from __future__ import annotations

from time import monotonic

from textual.app import ComposeResult
from textual.containers import Horizontal
from textual.content import Content
from textual.timer import Timer
from textual.widgets import Static

from .render import ToolCall, ToolResult

SPINNER = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
# Results replayed from history arrive at once; their time means nothing.
MIN_SHOWN_ELAPSED = 0.1


class ToolView(Horizontal):
    """The call on the left is cut to fit; the outcome on the right is always shown."""

    DEFAULT_CSS = """
    ToolView { height: 1; }
    ToolView > .call { width: 1fr; text-wrap: nowrap; text-overflow: ellipsis; }
    ToolView > .outcome { width: auto; padding: 0 0 0 2; }
    """

    def __init__(self, call: ToolCall) -> None:
        super().__init__(classes="tool")
        self.call = call
        self._started = monotonic()
        self._frame = 0
        self._timer: Timer | None = None

    def compose(self) -> ComposeResult:
        yield Static(classes="call")
        yield Static(classes="outcome")

    def on_mount(self) -> None:
        self._timer = self.set_interval(0.08, self._spin)
        self._draw((SPINNER[0], "$accent"))

    def _spin(self) -> None:
        self._frame += 1
        self._draw((SPINNER[self._frame % len(SPINNER)], "$accent"))

    def finish(self, result: ToolResult) -> None:
        if self._timer:
            self._timer.stop()
        elapsed = monotonic() - self._started
        tail = [result.summary] + ([f"{elapsed:.1f} с"] if elapsed >= MIN_SHOWN_ELAPSED else [])
        if result.ok:
            self._draw(("✓", "$success"), (" · ".join(tail), "dim"))
        else:
            # An error message is too long for the right column; it replaces the arguments.
            self._draw(("✗", "$error"), error=result.summary)

    def _draw(
        self, mark: tuple[str, str], tail: tuple[str, str] | None = None, error: str = ""
    ) -> None:
        parts: list[str | tuple[str, str]] = [mark, " ", (self.call.name, "bold")]
        if error:
            parts += ["  ", (error, "$error")]
        elif self.call.arguments:
            parts += ["  ", (self.call.arguments, "dim")]
        self.query_one(".call", Static).update(Content.assemble(*parts))
        self.query_one(".outcome", Static).update(Content.assemble(tail) if tail else "")
