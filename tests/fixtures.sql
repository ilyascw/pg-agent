-- Test helpers, installed once into the test database after the core.

create schema test;

create function test.echo(p_arguments jsonb, p_options jsonb) returns text
language sql immutable
as $$
    select coalesce(p_options ->> 'prefix', 'echo: ') || (p_arguments ->> 'text')
$$;

create table test.side_effect (note text);

create function test.fail_after_write(p_arguments jsonb, p_options jsonb) returns text
language plpgsql
as $$
begin
    insert into test.side_effect (note) values (p_arguments ->> 'note');
    raise exception 'tool exploded';
end
$$;

-- Agent "tester" on the fake model with tools echo and fail.
create function test.agent() returns void
language sql
as $$
    insert into llm.provider (name, adapter) values ('fake', 'llm_fake.complete(jsonb, jsonb)');

    insert into runtime.agent (name, provider, model, prompt)
    values ('tester', 'fake', 'fake-model', 'You are a test agent.');

    insert into tools.tool (name, description, parameters, handler) values
    (
        'echo',
        'Repeats text.',
        '{"type": "object", "properties": {"text": {"type": "string"}}, "required": ["text"]}',
        'test.echo(jsonb, jsonb)'
    ),
    ('fail', 'Always fails.', default, 'test.fail_after_write(jsonb, jsonb)');

    insert into tools.agent_tool (agent, tool) values ('tester', 'echo'), ('tester', 'fail');
$$;
