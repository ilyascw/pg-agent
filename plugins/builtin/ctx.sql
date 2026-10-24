-- Built-in context policies.

-- Keeps the last N user turns. Cuts only at user events, so a tool result is
-- never separated from the call that produced it. options: {"turns": int}
create function ctx.last_turns(p_state jsonb, p_options jsonb) returns jsonb
language sql stable
as $$
    with events as (
        select e.event, e.n
        from jsonb_array_elements(p_state -> 'events') with ordinality as e (event, n)
    ),

    cut as (
        select coalesce(min(u.n), 1) as n
        from (
            select events.n
            from events
            where events.event ->> 'kind' = 'user'
            order by events.n desc
            limit (p_options ->> 'turns')::int
        ) as u
    )

    select jsonb_set(
        p_state,
        '{events}',
        coalesce(
            (select jsonb_agg(events.event order by events.n) from events, cut where events.n >= cut.n),
            '[]'
        )
    )
$$;

-- Appends a paragraph to the system prompt. options: {"text": text}
create function ctx.append_system(p_state jsonb, p_options jsonb) returns jsonb
language sql stable
as $$
    select jsonb_set(
        p_state,
        '{system}',
        to_jsonb(concat_ws(e'\n\n', p_state ->> 'system', p_options ->> 'text'))
    )
$$;
