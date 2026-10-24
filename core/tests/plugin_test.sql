begin;

select plan(3);

select is(
    core.call_sql('ctx.append_system(jsonb, jsonb)'),
    'select ctx.append_system($1, $2)',
    'call_sql builds a qualified call with positional parameters'
);

select test.agent();

select throws_like(
    $$
        insert into tools.tool (name, description, handler)
        values ('bad', 'x', 'ctx.append_system(jsonb, jsonb)')
    $$,
    '%must be (jsonb, jsonb) returns text, got (jsonb, jsonb) returns jsonb%',
    'registry rejects a handler with the wrong signature'
);

select throws_like(
    $$
        insert into ctx.policy (agent, position, fn)
        values ('tester', 1, 'test.echo(jsonb, jsonb)')
    $$,
    '%must be (jsonb, jsonb) returns jsonb%',
    'every registry checks its own signature'
);

select * from finish();

rollback;
