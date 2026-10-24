begin;

select plan(4);

select test.agent();

create temp table s as select runtime.open('tester') as id;

select llm_fake.script(llm_fake.call('echo', '{"text": "ping"}'), llm_fake.say('pong'));
select runtime.send((select s.id from s), 'say ping');

select matches(
    tools.list_sessions('{}', '{"agent": "tester"}'),
    '^' || left((select s.id::text from s), 8) || '  \d{4}-\d\d-\d\d \d\d:\d\d  say ping$',
    'list shows id prefix, time and first message'
);

select is(
    tools.read_session(
        jsonb_build_object('session_id', left((select s.id::text from s), 8)), '{"agent": "tester"}'
    ),
    e'Пользователь: say ping\n\nАссистент: pong',
    'transcript without tool traffic'
);

select matches(
    tools.read_session('{"session_id": "zzz"}', '{"agent": "tester"}'),
    '^Сессия zzz не найдена',
    'unknown session'
);

select is(
    tools.list_sessions('{}', '{"agent": "nobody"}'),
    'Сессий нет.',
    'only the configured agent'
);

select * from finish();

rollback;
