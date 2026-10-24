from uuid import uuid4

from pg_agent import Event

from pg_agent_tui.render import Line, ToolCall, ToolResult, event_items, preview, prompt_tokens


def event(kind: str, **payload: object) -> Event:
    return Event(id=1, stream_id=uuid4(), kind=kind, payload=payload)


def test_model_text_comes_before_its_calls() -> None:
    lines = event_items(
        event(
            "model",
            text="Сейчас посмотрю",
            tool_calls=[{"id": "c", "name": "get_weather", "arguments": {"city": "Казань"}}],
        )
    )
    assert lines == [
        Line("answer", "Сейчас посмотрю"),
        ToolCall("c", "get_weather", 'city="Казань"'),
    ]


def test_tool_errors_are_marked() -> None:
    lines = event_items(
        event("tool_result", call_id="c", name="fail", content="boom\n", is_error=True)
    )
    assert lines == [ToolResult("c", "fail", False, "boom")]


def test_results_show_only_name_and_size() -> None:
    lines = event_items(event("tool_result", call_id="c", name="search", content='{"ok": true}'))
    assert lines == [ToolResult("c", "search", True, "12 Б")]


def test_long_lines_are_truncated() -> None:
    assert preview("x" * 10, limit=5) == "xxxx…"


def test_prompt_tokens_only_from_model_usage() -> None:
    assert prompt_tokens(event("model", text="hi", usage={"prompt_tokens": 42})) == 42
    assert prompt_tokens(event("model", text="hi", usage={})) is None
    assert prompt_tokens(event("user", text="hi")) is None
