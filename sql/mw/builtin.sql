-- Built-in middleware.

-- Tool calls the model made since the last user event, oldest first.
create function mw.turn_calls(p_events jsonb) returns jsonb
language sql stable
as $$
    with events as (
        select e.event, e.n
        from jsonb_array_elements(p_events) with ordinality as e (event, n)
    ),

    turn as (
        select coalesce(max(events.n), 0) as start
        from events
        where events.event ->> 'kind' = 'user'
    )

    select coalesce(
        jsonb_agg(
            jsonb_build_object('name', c.call -> 'name', 'arguments', c.call -> 'arguments')
            order by events.n, c.n
        ),
        '[]'
    )
    from events
    cross join turn
    cross join lateral jsonb_array_elements(events.event -> 'tool_calls') with ordinality as c (call, n)
    where events.n > turn.start and events.event ->> 'kind' = 'model'
$$;

-- before_llm. Forbids tools for the rest of the turn when the model made too many
-- calls or repeats the same call, and adds a hint to answer with what it has.
-- options: {"max_tool_steps": 8, "max_same_call": 2, "hint": text}
create function mw.loop_guard(p_request jsonb, p_options jsonb) returns jsonb
language plpgsql stable
as $$
declare
    v_calls jsonb := mw.turn_calls(p_request -> 'events');
    v_count int := jsonb_array_length(v_calls);
    v_max_steps int := coalesce((p_options ->> 'max_tool_steps')::int, 8);
    v_max_same int := coalesce((p_options ->> 'max_same_call')::int, 2);
    v_repeating boolean;
begin
    select v_count >= v_max_same and count(distinct c.call) = 1 into v_repeating
    from jsonb_array_elements(v_calls) with ordinality as c (call, n)
    where c.n > v_count - v_max_same;

    if v_count < v_max_steps and not v_repeating then
        return p_request;
    end if;

    return p_request || jsonb_build_object(
        'tool_choice', 'none',
        'events', (p_request -> 'events') || case
            when p_options ? 'hint' then
                jsonb_build_array(jsonb_build_object('kind', 'user', 'text', p_options -> 'hint'))
            else '[]'
        end
    );
end
$$;

-- after_llm. Removes arguments the model filled with an empty string instead of
-- omitting them, which some models do for optional parameters.
create function mw.drop_empty_arguments(p_response jsonb, p_options jsonb) returns jsonb
language sql stable
as $$
    select p_response || jsonb_build_object(
        'tool_calls',
        coalesce(
            (
                select jsonb_agg(
                    c.call || jsonb_build_object(
                        'arguments',
                        coalesce(
                            (
                                select jsonb_object_agg(a.key, a.value)
                                from jsonb_each(c.call -> 'arguments') as a (key, value)
                                where a.value <> '""'
                            ),
                            '{}'
                        )
                    )
                    order by c.n
                )
                from jsonb_array_elements(p_response -> 'tool_calls') with ordinality as c (call, n)
            ),
            '[]'
        )
    )
$$;
