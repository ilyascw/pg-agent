-- Model adapter layer. The rest of the core speaks one provider-neutral contract;
-- an adapter translates it to a concrete API.
--
-- Request:
--   {"model": text, "system": text, "events": [event], "tools": [tool],
--    "tool_choice": "auto" | "none"}
--   event: {"kind": "user", "text"}
--        | {"kind": "model", "text", "tool_calls"}
--        | {"kind": "tool_result", "call_id", "name", "content", "is_error"}
--   tool:  {"name", "description", "parameters": json schema, "examples": [...]}
--
-- Response:
--   {"text": text | null, "tool_calls": [call], "usage": {...}}
--   call: {"id", "name", "arguments": object}
--       | {"id", "name", "arguments": {}, "error": text} when the model sent garbage

create schema llm;

comment on schema llm is 'Model adapters behind a provider-neutral request/response contract.';

create table llm.provider (
    name text primary key,
    adapter regprocedure not null,
    config jsonb not null default '{}' check (jsonb_typeof(config) = 'object')
);

comment on column llm.provider.adapter is 'fn(config jsonb, request jsonb) returns jsonb';

create trigger provider_adapter_signature
before insert or update of adapter on llm.provider
for each row execute function core.require_signature('adapter', 'jsonb, jsonb', 'jsonb');

-- Validates an adapter response and fills defaults.
create function llm.check_response(p_response jsonb) returns jsonb
language plpgsql stable
as $$
declare
    v_calls jsonb := coalesce(p_response -> 'tool_calls', '[]');
begin
    if jsonb_typeof(p_response) is distinct from 'object' then
        raise exception 'llm response must be a json object, got %', p_response;
    end if;
    if jsonb_typeof(v_calls) <> 'array' then
        raise exception 'llm response tool_calls must be an array, got %', v_calls;
    end if;
    if exists (
        select
        from jsonb_array_elements(v_calls) as c (call)
        where
            c.call ->> 'id' is null
            or c.call ->> 'name' is null
            or jsonb_typeof(c.call -> 'arguments') is distinct from 'object'
    ) then
        raise exception 'malformed tool call in llm response: %', v_calls;
    end if;

    return jsonb_build_object(
        'text', coalesce(p_response -> 'text', 'null'),
        'tool_calls', v_calls,
        'usage', coalesce(p_response -> 'usage', '{}')
    );
end
$$;

create function llm.complete(p_provider text, p_request jsonb) returns jsonb
language plpgsql
as $$
declare
    v_provider llm.provider;
    v_response jsonb;
begin
    select * into v_provider from llm.provider where name = p_provider;
    if not found then
        raise exception 'unknown llm provider: %', p_provider;
    end if;

    execute core.call_sql(v_provider.adapter)
    into v_response
    using v_provider.config, p_request;
    return llm.check_response(v_response);
end
$$;
