from pg_agent_tui.commands import describe, matching


def names(text: str) -> list[str]:
    return [command.name for command in matching(text)]


def test_slash_lists_every_command() -> None:
    assert names("/") == ["/new", "/sessions", "/resume", "/tools", "/help", "/quit"]


def test_prefix_narrows_case_insensitively() -> None:
    assert names("/RE") == ["/resume"]


def test_no_hints_for_messages_or_arguments() -> None:
    assert names("привет") == []
    assert names("/resume 1a2b") == []
    assert names("/nope") == []


def test_describe_aligns_usage() -> None:
    assert describe(matching("/re")) == "/resume ID  продолжить сессию (достаточно начала ID)"
