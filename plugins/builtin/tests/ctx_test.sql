begin;

select plan(2);

select is(
    ctx.last_turns($${"system": "s", "events": [
        {"kind": "user", "text": "1"}, {"kind": "model", "text": "a1"},
        {"kind": "user", "text": "2"}, {"kind": "model", "tool_calls": []},
        {"kind": "tool_result", "content": "r"}, {"kind": "model", "text": "a2"},
        {"kind": "user", "text": "3"}
    ]}$$, '{"turns": 2}'),
    $${"system": "s", "events": [
        {"kind": "user", "text": "2"}, {"kind": "model", "tool_calls": []},
        {"kind": "tool_result", "content": "r"}, {"kind": "model", "text": "a2"},
        {"kind": "user", "text": "3"}
    ]}$$::jsonb,
    'last_turns cuts at a user event'
);

select is(
    ctx.last_turns('{"events": [{"kind": "user"}]}', '{"turns": 5}'),
    '{"events": [{"kind": "user"}]}',
    'last_turns keeps short histories'
);

select * from finish();

rollback;
