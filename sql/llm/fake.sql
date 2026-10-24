-- Scripted adapter for tests and demos: returns queued responses in order and
-- records the request each one answered.

create schema llm_fake;

comment on schema llm_fake is 'Scripted model adapter for tests.';

create table llm_fake.reply (
    id bigint generated always as identity primary key,
    response jsonb not null,
    request jsonb
);

create function llm_fake.say(p_text text) returns jsonb
language sql stable
as $$
    select jsonb_build_object('text', p_text, 'tool_calls', '[]'::jsonb)
$$;

create function llm_fake.call(p_name text, p_arguments jsonb default '{}') returns jsonb
language sql
as $$
    select jsonb_build_object(
        'text', null,
        'tool_calls', jsonb_build_array(jsonb_build_object(
            'id', 'call_' || gen_random_uuid(), 'name', p_name, 'arguments', p_arguments
        ))
    )
$$;

create function llm_fake.script(variadic p_responses jsonb[]) returns void
language sql
as $$
    insert into llm_fake.reply (response)
    select r.response from unnest(p_responses) with ordinality as r (response, n) order by r.n
$$;

create function llm_fake.complete(p_config jsonb, p_request jsonb) returns jsonb
language plpgsql
as $$
declare
    v_reply llm_fake.reply;
begin
    select * into v_reply
    from llm_fake.reply
    where request is null
    order by id
    limit 1
    for update;
    if not found then
        raise exception 'llm_fake: no scripted replies left';
    end if;

    update llm_fake.reply set request = p_request where id = v_reply.id;
    return v_reply.response;
end
$$;
