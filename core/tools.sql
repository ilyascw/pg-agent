-- Tools: a registry of handlers and which agent may use which tool. A handler is
-- fn(arguments jsonb, options jsonb) returns text, where options come from the tool
-- row, so one handler can serve many tools (see mcp). Errors it raises are rolled
-- back and returned to the model as an error result, so the loop never crashes.

create schema tools;

comment on schema tools is 'Tool registry and execution.';

create table tools.tool (
    name text primary key check (name ~ '^[a-z][a-z0-9_]{0,63}$'),
    description text not null,
    parameters jsonb not null default '{"type": "object", "properties": {}}'
    check (parameters ->> 'type' = 'object'),
    handler regprocedure not null,
    options jsonb not null default '{}' check (jsonb_typeof(options) = 'object'),
    -- Example calls for endpoints that accept them: [{"request", "params"}].
    examples jsonb not null default '[]' check (jsonb_typeof(examples) = 'array')
);

create trigger tool_handler_signature
before insert or update of handler on tools.tool
for each row execute function core.require_signature('handler', 'jsonb, jsonb', 'text');

create table tools.agent_tool (
    agent text not null references runtime.agent on delete cascade,
    tool text not null references tools.tool on delete cascade,
    primary key (agent, tool)
);

create function tools.schemas(p_agent text) returns jsonb
language sql stable
as $$
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'name', t.name,
                'description', t.description,
                'parameters', t.parameters,
                'examples', t.examples
            )
            order by t.name
        ),
        '[]'
    )
    from tools.tool as t
    inner join tools.agent_tool as a on t.name = a.tool
    where a.agent = p_agent
$$;

create function tools.result(p_call jsonb, p_content text, p_is_error boolean) returns jsonb
language sql stable
as $$
    select jsonb_build_object(
        'call_id', p_call -> 'id',
        'name', p_call -> 'name',
        'content', p_content,
        'is_error', p_is_error
    )
$$;

-- Runs one tool call from a model response; returns a tool_result event payload.
create function tools.execute(p_agent text, p_call jsonb) returns jsonb
language plpgsql
as $$
declare
    v_tool tools.tool;
    v_missing text;
    v_content text;
begin
    if p_call ? 'error' then
        return tools.result(p_call, p_call ->> 'error', true);
    end if;

    select t.* into v_tool
    from tools.tool as t
    inner join tools.agent_tool as a on t.name = a.tool
    where a.agent = p_agent and t.name = p_call ->> 'name';
    if not found then
        return tools.result(
            p_call,
            format(
                'unknown tool %s, available: %s',
                p_call ->> 'name',
                (select string_agg(tool, ', ' order by tool) from tools.agent_tool where agent = p_agent)
            ),
            true
        );
    end if;

    select string_agg(r.name, ', ') into v_missing
    from jsonb_array_elements_text(coalesce(v_tool.parameters -> 'required', '[]')) as r (name)
    where not (p_call -> 'arguments') ? r.name;
    if v_missing is not null then
        return tools.result(p_call, 'missing required arguments: ' || v_missing, true);
    end if;

    begin
        execute core.call_sql(v_tool.handler)
        into v_content
        using p_call -> 'arguments', v_tool.options;
    exception when others then
        return tools.result(p_call, sqlerrm, true);
    end;
    return tools.result(p_call, coalesce(v_content, ''), false);
end
$$;
