begin;

select plan(7);

select is(
    llm_openai.messages('sys', $$[
        {"kind": "user", "text": "hi"},
        {"kind": "model", "text": null, "tool_calls": [{"id": "c1", "name": "echo", "arguments": {"text": "a"}}]},
        {"kind": "tool_result", "call_id": "c1", "name": "echo", "content": "echo: a", "is_error": false},
        {"kind": "model", "text": "done", "tool_calls": []}
    ]$$),
    $$[
        {"role": "system", "content": "sys"},
        {"role": "user", "content": "hi"},
        {"role": "assistant", "content": null, "tool_calls": [
            {"id": "c1", "type": "function", "function": {"name": "echo", "arguments": "{\"text\": \"a\"}"}}
        ]},
        {"role": "tool", "tool_call_id": "c1", "name": "echo", "content": "echo: a"},
        {"role": "assistant", "content": "done"}
    ]$$::jsonb,
    'events map to chat messages'
);

select is(
    llm_openai.body(
        '{"tool_examples_field": "few_shot_examples", "temperature": 0.3}',
        $${"model": "m", "system": null, "events": [], "tool_choice": "none", "tools": [
            {"name": "echo", "description": "d", "parameters": {"type": "object"},
             "examples": [{"request": "r", "params": {}}]}
        ]}$$
    ),
    $${"model": "m", "messages": [], "tool_choice": "none", "temperature": 0.3, "tools": [
        {"type": "function", "function": {"name": "echo", "description": "d",
         "parameters": {"type": "object"}, "few_shot_examples": [{"request": "r", "params": {}}]}}
    ]}$$::jsonb,
    'body carries tools, tool_choice, options and few-shot examples'
);

select ok(
    not llm_openai.body('{}', '{"model": "m", "events": [], "tools": []}') ? 'tool_choice',
    'no tools means no tool_choice'
);

select is(
    llm_openai.parse($${"usage": {"total_tokens": 5}, "choices": [{"message": {
        "content": null,
        "tool_calls": [{"id": "c1", "type": "function", "function": {"name": "echo", "arguments": "{\"text\":\"a\"}"}}]
    }}]}$$),
    $${"text": null, "usage": {"total_tokens": 5},
       "tool_calls": [{"id": "c1", "name": "echo", "arguments": {"text": "a"}}]}$$::jsonb,
    'tool call arguments are decoded'
);

select is(
    llm_openai.parse('{"choices": [{"message": {"content": "hello"}}]}'),
    '{"text": "hello", "tool_calls": [], "usage": {}}',
    'plain answer'
);

select is(
    llm_openai.call('{"id": "c1", "function": {"name": "echo", "arguments": "{oops"}}') ->> 'error',
    'arguments are not valid JSON: {oops',
    'broken arguments become a call error instead of an exception'
);

select is(
    llm_openai.call('{"id": "c1", "function": {"name": "echo", "arguments": ""}}') -> 'arguments',
    '{}',
    'empty arguments string is an empty object'
);

select * from finish();

rollback;
