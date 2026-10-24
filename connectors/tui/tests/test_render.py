from uuid import uuid4

from pg_agent import Event
from pg_agent_tui.render import Line, event_lines, preview, prompt_tokens


def event(kind: str, **payload: object) -> Event:
    return Event(id=1, stream_id=uuid4(), kind=kind, payload=payload)


def test_model_text_comes_before_its_calls() -> None:
    lines = event_lines(
        event(
            "model",
            text="Сейчас посмотрю",
            tool_calls=[{"id": "c", "name": "get_weather", "arguments": {"city": "Казань"}}],
        )
    )
    assert lines == [
        Line("answer", "Сейчас посмотрю"),
        Line("call", 'get_weather(city="Казань")'),
    ]


def test_tool_errors_are_marked() -> None:
    lines = event_lines(event("tool_result", name="fail", content="boom", is_error=True))
    assert lines == [Line("error", "fail: boom")]


def test_long_results_are_truncated() -> None:
    assert preview("x" * 10, limit=5) == "xxxx…"


def test_prompt_tokens_only_from_model_usage() -> None:
    assert prompt_tokens(event("model", text="hi", usage={"prompt_tokens": 42})) == 42
    assert prompt_tokens(event("model", text="hi", usage={})) is None
    assert prompt_tokens(event("user", text="hi")) is None
