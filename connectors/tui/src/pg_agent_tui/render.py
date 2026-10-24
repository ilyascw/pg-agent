"""Turns core events into display items; no Textual here, so it is easy to test."""

from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any, Literal

from pg_agent import Event

PREVIEW = 100

LineKind = Literal["user", "answer", "error"]


@dataclass(frozen=True, slots=True)
class Line:
    kind: LineKind
    text: str


@dataclass(frozen=True, slots=True)
class ToolCall:
    id: str
    name: str
    arguments: str


@dataclass(frozen=True, slots=True)
class ToolResult:
    call_id: str
    name: str
    ok: bool
    # Response size on success, the error message otherwise.
    summary: str


Item = Line | ToolCall | ToolResult


def event_items(event: Event) -> list[Item]:
    payload = event.payload
    if event.kind == "user":
        return [Line("user", payload.get("text") or "")]
    if event.kind == "model":
        items: list[Item] = [Line("answer", payload["text"])] if payload.get("text") else []
        items += [
            ToolCall(str(call.get("id")), call["name"], format_arguments(call["arguments"]))
            for call in payload.get("tool_calls") or []
        ]
        return items
    if event.kind == "tool_result":
        content = payload.get("content") or ""
        ok = not payload.get("is_error")
        return [
            ToolResult(
                str(payload.get("call_id")),
                payload.get("name") or "",
                ok,
                size(content) if ok else preview(" ".join(content.split())),
            )
        ]
    return []


def format_arguments(arguments: dict[str, Any]) -> str:
    return preview(
        "  ".join(
            f"{name}={json.dumps(value, ensure_ascii=False)}" for name, value in arguments.items()
        )
    )


def size(text: str) -> str:
    length = len(text.encode())
    return f"{length} Б" if length < 1024 else f"{length / 1024:.1f} КБ"


def preview(text: str, limit: int = PREVIEW) -> str:
    return text if len(text) <= limit else text[: limit - 1] + "…"


def prompt_tokens(event: Event) -> int | None:
    """Size of the context the model saw, when the endpoint reports usage."""
    if event.kind != "model":
        return None
    value = (event.payload.get("usage") or {}).get("prompt_tokens")
    return value if isinstance(value, int) else None
