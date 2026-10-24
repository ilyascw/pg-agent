-- The agent loop: assemble context, call the model through middleware, record the
-- response, run requested tools, repeat until the model answers without tools.

create function runtime.open(p_agent text) returns uuid
language sql
as $$
    select core.open_stream(p_agent)
$$;

-- One model call plus the tools it requested. True when the model gave a final answer.
create function runtime.step(p_stream uuid) returns boolean
language plpgsql
as $$
declare
    v_agent runtime.agent;
    v_context jsonb;
    v_request jsonb;
    v_response jsonb;
    v_call jsonb;
begin
    select a.* into v_agent
    from runtime.agent as a
    inner join core.stream as s on a.name = s.agent
    where s.id = p_stream;
    if not found then
        raise exception 'unknown stream %', p_stream;
    end if;

    v_context := ctx.assemble(v_agent.name, core.history(p_stream));
    v_request := mw.apply(v_agent.name, 'before_llm', jsonb_build_object(
        'model', v_agent.model,
        'system', v_context -> 'system',
        'events', v_context -> 'events',
        'tools', tools.schemas(v_agent.name),
        'tool_choice', 'auto'
    ));
    v_response := llm.check_response(
        mw.apply(v_agent.name, 'after_llm', llm.complete(v_agent.provider, v_request))
    );
    perform core.append(p_stream, 'model', v_response);

    for v_call in select c.call from jsonb_array_elements(v_response -> 'tool_calls') as c (call) loop
        perform core.append(p_stream, 'tool_result', tools.execute(v_agent.name, v_call));
    end loop;
    return jsonb_array_length(v_response -> 'tool_calls') = 0;
end
$$;

create function runtime.last_answer(p_stream uuid) returns text
language sql stable
as $$
    select e.payload ->> 'text'
    from core.event as e
    where e.stream_id = p_stream and e.kind = 'model'
    order by e.id desc
    limit 1
$$;

create function runtime.max_llm_calls(p_stream uuid) returns int
language sql stable
as $$
    select a.max_llm_calls
    from runtime.agent as a
    inner join core.stream as s on a.name = s.agent
    where s.id = p_stream
$$;

-- Whole turn in the caller's transaction: atomic, but connectors see its events only
-- at the end. Use from tests and from code that composes turns with other writes.
create function runtime.send(p_stream uuid, p_text text) returns text
language plpgsql
as $$
declare
    v_limit int := runtime.max_llm_calls(p_stream);
begin
    perform core.append(p_stream, 'user', jsonb_build_object('text', p_text));
    for i in 1..v_limit loop
        if runtime.step(p_stream) then
            return runtime.last_answer(p_stream);
        end if;
    end loop;
    raise exception 'agent did not answer within % model calls', v_limit;
end
$$;

-- Same turn, committing after every step so LISTENers see events as they happen and a
-- failure keeps completed steps. Connectors use this: CALL runtime.run(stream, text, null).
create procedure runtime.run(p_stream uuid, p_text text, inout p_answer text default null)
language plpgsql
as $$
declare
    v_limit int := runtime.max_llm_calls(p_stream);
begin
    perform core.append(p_stream, 'user', jsonb_build_object('text', p_text));
    commit;
    for i in 1..v_limit loop
        if runtime.step(p_stream) then
            p_answer := runtime.last_answer(p_stream);
            return;
        end if;
        commit;
    end loop;
    raise exception 'agent did not answer within % model calls', v_limit;
end
$$;
