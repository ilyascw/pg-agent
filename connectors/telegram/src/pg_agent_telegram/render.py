"""Core events and model answers as Telegram text; no aiogram here, so it is easy to test."""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from typing import Any

import telegramify_markdown
from pg_agent import Event

# Telegram limit for one message, in UTF-16 code units.
MESSAGE_LIMIT = 4096
CALL_PREVIEW = 120

PENDING, DONE, FAILED = "⏳", "✅", "❌"


def call_line(call: dict[str, Any]) -> str:
    arguments = ", ".join(
        f"{name}={json.dumps(value, ensure_ascii=False)}"
        for name, value in (call.get("arguments") or {}).items()
    )
    line = f"{call['name']}({arguments})"
    return line if len(line) <= CALL_PREVIEW else line[: CALL_PREVIEW - 1] + "…"


@dataclass
class Status:
    """Tool calls of one turn, each marked pending, done or failed."""

    calls: dict[str, list[str]] = field(default_factory=dict)

    def apply(self, event: Event) -> bool:
        """Record the event; true when the text changed."""
        if event.kind == "model":
            for call in event.payload.get("tool_calls") or []:
                self.calls[call["id"]] = [PENDING, call_line(call)]
            return bool(event.payload.get("tool_calls"))
        if event.kind == "tool_result" and event.payload.get("call_id") in self.calls:
            mark = FAILED if event.payload.get("is_error") else DONE
            self.calls[event.payload["call_id"]][0] = mark
            return True
        return False

    def text(self) -> str:
        return "\n".join(f"{mark} {line}" for mark, line in self.calls.values())


def answer_parts(markdown: str) -> list[tuple[str, list[dict[str, Any]]]]:
    """Markdown answer as Telegram messages: plain text plus entities, split to fit."""
    text, entities = telegramify_markdown.convert(markdown)
    return [
        (chunk, [entity.to_dict() for entity in chunk_entities])
        for chunk, chunk_entities in telegramify_markdown.split_entities(
            text, entities, MESSAGE_LIMIT
        )
    ]
