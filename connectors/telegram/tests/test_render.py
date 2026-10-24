from uuid import uuid4

from pg_agent import Event

from pg_agent_telegram.render import MESSAGE_LIMIT, Status, answer_parts, call_line


def event(kind: str, **payload: object) -> Event:
    return Event(id=1, stream_id=uuid4(), kind=kind, payload=payload)


def test_status_marks_calls_by_result() -> None:
    status = Status()
    calls = [
        {"id": "1", "name": "weather", "arguments": {"city": "Москва"}},
        {"id": "2", "name": "rate", "arguments": {}},
    ]
    assert status.apply(event("model", text=None, tool_calls=calls))
    assert status.text() == '⏳ weather(city="Москва")\n⏳ rate()'

    assert status.apply(event("tool_result", call_id="1", is_error=False))
    assert status.apply(event("tool_result", call_id="2", is_error=True))
    assert status.text() == '✅ weather(city="Москва")\n❌ rate()'


def test_status_ignores_answers_and_user_text() -> None:
    status = Status()
    assert not status.apply(event("user", text="hi"))
    assert not status.apply(event("model", text="hello", tool_calls=[]))
    assert status.text() == ""


def test_long_call_is_cut() -> None:
    line = call_line({"name": "note", "arguments": {"text": "x" * 500}})
    assert len(line) == 120 and line.endswith("…")


def test_answer_markdown_becomes_entities() -> None:
    [(text, entities)] = answer_parts("**жирный** и `код`")
    assert text.strip() == "жирный и код"
    assert [e["type"] for e in entities] == ["bold", "code"]


def test_long_answer_is_split() -> None:
    parts = answer_parts("\n\n".join(["слово " * 100] * 20))
    assert len(parts) > 1
    assert all(len(text) <= MESSAGE_LIMIT for text, _ in parts)
