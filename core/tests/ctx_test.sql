begin;

select plan(2);

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
