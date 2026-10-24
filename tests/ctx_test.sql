begin;

select plan(4);

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

select test.agent();

insert into ctx.policy (agent, position, fn, options) values
('tester', 2, 'ctx.append_system(jsonb, jsonb)', '{"text": "second"}'),
('tester', 1, 'ctx.append_system(jsonb, jsonb)', '{"text": "first"}');

select is(
    ctx.assemble('tester', '[]') ->> 'system',
    e'You are a test agent.\n\nfirst\n\nsecond',
    'policies run in position order on top of the agent prompt'
);

select is(
    ctx.assemble('tester', '[{"kind": "user"}]') -> 'events',
    '[{"kind": "user"}]',
    'events pass through'
);

select * from finish();

rollback;
