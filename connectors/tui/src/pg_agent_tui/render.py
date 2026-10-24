"""Turns core events into display lines; no Textual here, so it is easy to test."""

from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any, Literal

from pg_agent import Event

RESULT_PREVIEW = 300

LineKind = Literal["user", "answer", "call", "result", "error"]


@dataclass(frozen=True, slots=True)
class Line:
    kind: LineKind
    text: str


def event_lines(event: Event) -> list[Line]:
    payload = event.payload
    if event.kind == "user":
        return [Line("user", payload.get("text") or "")]
    if event.kind == "model":
        lines = [Line("answer", payload["text"])] if payload.get("text") else []
        lines += [
            Line("call", f"{call['name']}({format_arguments(call['arguments'])})")
            for call in payload.get("tool_calls") or []
        ]
        return lines
    if event.kind == "tool_result":
        kind: LineKind = "error" if payload.get("is_error") else "result"
        return [Line(kind, f"{payload.get('name')}: {preview(payload.get('content') or '')}")]
    return []


def format_arguments(arguments: dict[str, Any]) -> str:
    return ", ".join(
        f"{name}={json.dumps(value, ensure_ascii=False)}" for name, value in arguments.items()
    )


def preview(text: str, limit: int = RESULT_PREVIEW) -> str:
    return text if len(text) <= limit else text[: limit - 1] + "…"


def prompt_tokens(event: Event) -> int | None:
    """Size of the context the model saw, when the endpoint reports usage."""
    if event.kind != "model":
        return None
    value = (event.payload.get("usage") or {}).get("prompt_tokens")
    return value if isinstance(value, int) else None
