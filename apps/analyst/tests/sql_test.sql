-- run_sql reads through its own session, so the fixture is committed first.
set client_min_messages = warning;
drop schema if exists demo cascade;
create schema demo;
create table demo.city (name text, population int, note text);
insert into demo.city values
('Москва', 13100000, 'столица'),
('Казань', 1300000, e'a|b\nc'),
('Тверь', 400000, null);
grant usage on schema demo to analyst_reader;
grant select on demo.city to analyst_reader;

begin;

select plan(13);

select is(
    analyst.run_sql(
        '{"sql": "select population, name from demo.city order by population desc limit 2;"}', '{}'
    ),
    e'| population | name |\n| --- | --- |\n'
    || e'| 13100000 | Москва |\n| 1300000 | Казань |\n\nСтрок: 2.',
    'result is a Markdown table in select order; a trailing semicolon is fine'
);

select is(
    analyst.run_sql('{"sql": "select note from demo.city order by population"}', '{}'),
    e'| note |\n| --- |\n|  |\n| a b c |\n| столица |\n\nСтрок: 3.',
    'nulls are empty, pipes and newlines do not break the table'
);

select matches(
    analyst.run_sql('{"sql": "select name from demo.city"}', '{"max_rows": 2}'),
    'Показаны первые 2 строк, есть ещё',
    'rows beyond max_rows are cut with a hint'
);

select is(
    analyst.run_sql('{"sql": "select name from demo.city where false"}', '{}'),
    'Запрос вернул 0 строк.',
    'empty result'
);

select matches(
    analyst.run_sql('{"sql": "select pg_sleep(5)"}', '{"timeout_s": 0.3}'),
    '^Запрос не уложился в 0.3 с и отменён',
    'slow queries are cancelled at the deadline'
);

select is(
    analyst.run_sql(
        jsonb_build_object(
            'sql', 'select 1 as a) as q) as t; set statement_timeout = 0; select * from (select (1'
        ),
        '{"timeout_s": 5}'
    ),
    e'| a |\n| --- |\n| 1 |\n\nСтрок: 1.',
    'statements smuggled past the wrapper do not change the result'
);

select throws_ok(
    $$select analyst.run_sql('{"sql": "delete from demo.city"}', '{}')$$,
    '42601',
    null,
    'data changes do not parse as a subquery'
);

select throws_ok(
    $$select analyst.run_sql('{"sql": "select 1; drop table demo.city"}', '{}')$$,
    '42601',
    null,
    'a second statement does not parse'
);

select throws_ok(
    $$select analyst.run_sql('{"sql": "select count(*) from core.event"}', '{}')$$,
    '42501',
    null,
    'agent internals are not readable'
);

select throws_ok(
    $$select analyst.run_sql('{"sql": "select public.urlencode(''x'')"}', '{}')$$,
    '42501',
    null,
    'functions of extensions in public, pgsql-http among them, are not callable'
);

insert into skills.skill (library, name, description, content)
values ('analyst', 'demo_city', 'города и население', '# demo.city');

select matches(
    ctx.assemble('analyst', '[]') ->> 'system',
    'Каталог таблиц.*\n- demo_city — города и население',
    'the system prompt carries the table catalog'
);

select is(
    (
        select count(*) from tools.agent_tool
        where agent = 'analyst'
    ),
    2::bigint,
    'the analyst has run_sql and load_table_skill'
);

select throws_ok(
    $$select analyst.run_sql('{"sql": "select analyst.dblink_get_connections()"}', '{}')$$,
    '42501',
    null,
    'the query cannot reach dblink'
);

select * from finish();

rollback;

drop schema demo cascade;
