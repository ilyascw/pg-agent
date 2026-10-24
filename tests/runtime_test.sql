begin;

select plan(8);

select test.agent();

insert into mw.middleware (agent, hook, position, fn, options)
values ('tester', 'before_llm', 1, 'mw.loop_guard(jsonb, jsonb)', '{"max_tool_steps": 2}');

create temp table s as select runtime.open('tester') as id;

select llm_fake.script(
    llm_fake.call('echo', '{"text": "ping"}'),
    llm_fake.say('pong')
);

select is(
    runtime.send((select s.id from s), 'say ping'),
    'pong',
    'turn ends with the final answer'
);

select is(
    (
        select array_agg(kind order by id) from core.event
        where stream_id = (select s.id from s)
    ),
    array['user', 'model', 'tool_result', 'model'],
    'every step is in the event log'
);

select is(
    (
        select payload ->> 'content' from core.event
        where stream_id = (select s.id from s) and kind = 'tool_result'
    ),
    'echo: ping',
    'tool result is recorded'
);

select is(
    (
        select request -> 'events' -> -1 ->> 'content' from llm_fake.reply
        order by id desc limit 1
    ),
    'echo: ping',
    'second model call sees the tool result'
);

select is(
    (
        select request -> 'system' from llm_fake.reply
        order by id limit 1
    ),
    '"You are a test agent."',
    'model gets the assembled system prompt'
);

select llm_fake.script(
    llm_fake.call('echo', '{"text": "1"}'),
    llm_fake.call('echo', '{"text": "2"}'),
    llm_fake.say('stopped')
);

select runtime.send((select s.id from s), 'loop');

select is(
    (
        select request ->> 'tool_choice' from llm_fake.reply
        order by id desc limit 1
    ),
    'none',
    'loop guard middleware forbids tools after the limit'
);

select is(
    (select array[s.title, s.events::text] from core.streams('tester') as s),
    array['say ping', '10'],
    'streams list conversations with their first message'
);

update runtime.agent set max_llm_calls = 1;

select llm_fake.script(llm_fake.call('echo', '{"text": "again"}'));

select throws_ok(
    $$ select runtime.send((select s.id from s), 'never ends') $$,
    'agent did not answer within 1 model calls',
    'hard limit on model calls per turn'
);

select * from finish();

rollback;
