-- Adapter for any OpenAI-compatible Chat Completions endpoint.
-- Pure mapping functions are separate from the HTTP call so they can be tested
-- without a network.
--
-- config: {"base_url", "api_key", "timeout": seconds, "temperature",
--          "tool_examples_field": text -- function field that carries tool examples,
--                                         for endpoints that accept them; omit otherwise}

create schema llm_openai;

comment on schema llm_openai is 'OpenAI Chat Completions adapter.';

create function llm_openai.message(p_event jsonb) returns jsonb
language plpgsql stable
as $$
begin
    case p_event ->> 'kind'
        when 'user' then
            return jsonb_build_object('role', 'user', 'content', p_event -> 'text');
        when 'model' then
            return jsonb_build_object('role', 'assistant', 'content', p_event -> 'text')
                || case
                    when jsonb_array_length(p_event -> 'tool_calls') > 0 then
                        jsonb_build_object('tool_calls', (
                            select jsonb_agg(jsonb_build_object(
                                'id', c.call -> 'id',
                                'type', 'function',
                                'function', jsonb_build_object(
                                    'name', c.call -> 'name',
                                    'arguments', (c.call -> 'arguments')::text
                                )
                            ) order by c.n)
                            from jsonb_array_elements(p_event -> 'tool_calls')
                                with ordinality as c (call, n)
                        ))
                    else '{}'
                end;
        when 'tool_result' then
            return jsonb_build_object(
                'role', 'tool',
                'tool_call_id', p_event -> 'call_id',
                'name', p_event -> 'name',
                'content', p_event -> 'content'
            );
        else
            raise exception 'unknown event kind: %', p_event ->> 'kind';
    end case;
end
$$;

create function llm_openai.messages(p_system text, p_events jsonb) returns jsonb
language sql stable
as $$
    select
        case
            when p_system is null then '[]'
            else jsonb_build_array(jsonb_build_object('role', 'system', 'content', p_system))
        end
        || coalesce(
            (
                select jsonb_agg(llm_openai.message(e.event) order by e.n)
                from jsonb_array_elements(p_events) with ordinality as e (event, n)
            ),
            '[]'
        )
$$;

create function llm_openai.tools(p_tools jsonb, p_examples_field text) returns jsonb
language sql stable
as $$
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'type', 'function',
                'function', jsonb_build_object(
                    'name', t.tool -> 'name',
                    'description', t.tool -> 'description',
                    'parameters', t.tool -> 'parameters'
                ) || case
                    when
                        p_examples_field is not null
                        and jsonb_array_length(coalesce(t.tool -> 'examples', '[]')) > 0
                        then jsonb_build_object(p_examples_field, t.tool -> 'examples')
                    else '{}'
                end
            )
            order by t.n
        ),
        '[]'
    )
    from jsonb_array_elements(coalesce(p_tools, '[]')) with ordinality as t (tool, n)
$$;

create function llm_openai.body(p_config jsonb, p_request jsonb) returns jsonb
language plpgsql stable
as $$
declare
    v_tools jsonb := llm_openai.tools(p_request -> 'tools', p_config ->> 'tool_examples_field');
    v_body jsonb := jsonb_build_object(
        'model', p_request -> 'model',
        'messages', llm_openai.messages(p_request ->> 'system', p_request -> 'events')
    );
begin
    if jsonb_array_length(v_tools) > 0 then
        v_body := v_body || jsonb_build_object(
            'tools', v_tools,
            'tool_choice', coalesce(p_request -> 'tool_choice', '"auto"')
        );
    end if;
    if p_config ? 'temperature' then
        v_body := v_body || jsonb_build_object('temperature', p_config -> 'temperature');
    end if;
    return v_body;
end
$$;

-- Tool call from the wire: arguments arrive as a JSON string.
create function llm_openai.call(p_call jsonb) returns jsonb
language plpgsql stable
as $$
declare
    v_raw jsonb := p_call -> 'function' -> 'arguments';
    v_call jsonb := jsonb_build_object(
        'id', p_call -> 'id',
        'name', p_call -> 'function' -> 'name',
        'arguments', '{}'::jsonb
    );
    v_arguments jsonb;
begin
    if jsonb_typeof(v_raw) = 'object' then
        v_arguments := v_raw;
    elsif v_raw is null or jsonb_typeof(v_raw) = 'null' or v_raw #>> '{}' = '' then
        v_arguments := '{}';
    else
        begin
            v_arguments := (v_raw #>> '{}')::jsonb;
        exception when invalid_text_representation then
            return v_call || jsonb_build_object('error', 'arguments are not valid JSON: ' || (v_raw #>> '{}'));
        end;
    end if;

    if jsonb_typeof(v_arguments) <> 'object' then
        return v_call || jsonb_build_object('error', 'arguments must be a JSON object: ' || v_arguments::text);
    end if;
    return jsonb_set(v_call, '{arguments}', v_arguments);
end
$$;

create function llm_openai.parse(p_body jsonb) returns jsonb
language sql stable
as $$
    select jsonb_build_object(
        'text', coalesce(m.message -> 'content', 'null'),
        'tool_calls', case
            when jsonb_typeof(m.message -> 'tool_calls') = 'array' then coalesce(
                (
                    select jsonb_agg(llm_openai.call(c.call) order by c.n)
                    from jsonb_array_elements(m.message -> 'tool_calls') with ordinality as c (call, n)
                ),
                '[]'
            )
            else '[]'
        end,
        'usage', coalesce(p_body -> 'usage', '{}')
    )
    from (select p_body -> 'choices' -> 0 -> 'message' as message) as m
$$;

create function llm_openai.complete(p_config jsonb, p_request jsonb) returns jsonb
language plpgsql
as $$
declare
    v_response public.http_response;
begin
    -- curl options are per session, so set both: the connect timeout defaults to 1 second.
    perform public.http_set_curlopt('CURLOPT_CONNECTTIMEOUT', '10');
    perform public.http_set_curlopt('CURLOPT_TIMEOUT', coalesce(p_config ->> 'timeout', '180'));
    v_response := public.http((
        'POST',
        rtrim(p_config ->> 'base_url', '/') || '/chat/completions',
        array[public.http_header('Authorization', 'Bearer ' || coalesce(p_config ->> 'api_key', '0'))],
        'application/json',
        llm_openai.body(p_config, p_request)::text
    )::public.http_request);

    if v_response.status not between 200 and 299 then
        raise exception 'llm request failed: HTTP % %', v_response.status, left(v_response.content, 500);
    end if;
    return llm_openai.parse(v_response.content::jsonb);
end
$$;
