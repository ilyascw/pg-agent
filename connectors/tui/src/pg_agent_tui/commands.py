"""Slash commands of the chat: one list drives hints, completion and /help."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class Command:
    name: str
    description: str
    argument: str = ""

    @property
    def usage(self) -> str:
        return f"{self.name} {self.argument}".strip()


COMMANDS = (
    Command("/new", "новая сессия"),
    Command("/sessions", "последние сессии"),
    Command("/resume", "продолжить сессию (достаточно начала ID)", "ID"),
    Command("/tools", "инструменты агента"),
    Command("/help", "эта справка"),
    Command("/quit", "выход"),
)


def matching(text: str) -> list[Command]:
    """Commands that the input may still turn into; none once arguments start."""
    if not text.startswith("/") or " " in text:
        return []
    return [command for command in COMMANDS if command.name.startswith(text.lower())]


def describe(commands: list[Command] | tuple[Command, ...] = COMMANDS) -> str:
    width = max(len(command.usage) for command in commands)
    return "\n".join(f"{c.usage:<{width}}  {c.description}" for c in commands)
