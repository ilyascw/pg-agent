begin;

select plan(4);

select is(
    (
        select count(*)::int from tools.agent_tool
        where agent = 'personal'
    ),
    14,
    'all personal and session tools are granted'
);

select ok(
    (
        select config ? 'base_url' from llm.provider
        where name = 'openai'
    ),
    'provider is configured from install variables'
);

select matches(
    personal.load_skill('{"name": "financial_model"}'),
    'calculate',
    'skills are seeded'
);

-- One full turn of the real agent definition with a scripted model.
insert into llm.provider (name, adapter) values ('fake', 'llm_fake.complete(jsonb, jsonb)');
update runtime.agent set provider = 'fake'
where name = 'personal';

select llm_fake.script(
    llm_fake.call('save_note', '{"text": "купить молоко", "tags": ""}'),
    llm_fake.say('Записал.')
);

select is(runtime.send(runtime.open('personal'), 'запомни купить молоко'), 'Записал.', 'turn');

select * from finish();

rollback;
