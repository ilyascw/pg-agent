begin;

select plan(7);

select test.agent();

select is(
    tools.execute('tester', '{"id": "c1", "name": "echo", "arguments": {"text": "hi"}}'),
    '{"call_id": "c1", "name": "echo", "content": "echo: hi", "is_error": false}',
    'runs the handler'
);

select is(
    tools.execute('tester', '{"id": "c1", "name": "nope", "arguments": {}}') ->> 'content',
    'unknown tool nope, available: echo, fail',
    'unknown tool lists available ones'
);

select is(
    tools.execute('tester', '{"id": "c1", "name": "echo", "arguments": {}}') ->> 'content',
    'missing required arguments: text',
    'required arguments are checked'
);

select is(
    tools.execute('tester', '{"id": "c1", "name": "fail", "arguments": {"note": "x"}}'),
    '{"call_id": "c1", "name": "fail", "content": "tool exploded", "is_error": true}',
    'handler error becomes an error result'
);

select is_empty('select * from test.side_effect', 'failed handler writes are rolled back');

update tools.tool set options = '{"prefix": "> "}'
where name = 'echo';

select is(
    tools.execute('tester', '{"id": "c1", "name": "echo", "arguments": {"text": "hi"}}')
    ->> 'content',
    '> hi',
    'tool options reach the handler'
);

select is(
    jsonb_array_length(tools.schemas('tester')),
    2,
    'schemas list tools granted to the agent'
);

select * from finish();

rollback;
