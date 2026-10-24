-- Built-in tools that let an agent read its own past conversations.
-- options: {"agent": name} — whose streams to show.

create function tools.list_sessions(p_arguments jsonb, p_options jsonb) returns text
language sql stable
as $$
    select coalesce(
        string_agg(
            format(
                '%s  %s  %s',
                left(s.id::text, 8),
                to_char(s.created_at, 'YYYY-MM-DD HH24:MI'),
                coalesce(s.title, '—')
            ),
            e'\n' order by s.created_at desc
        ),
        'Сессий нет.'
    )
    from core.streams(
        p_options ->> 'agent',
        coalesce((p_arguments ->> 'limit')::int, 10)
    ) as s
$$;

-- Conversation text without tool traffic. The session is found by an id prefix.
create function tools.read_session(p_arguments jsonb, p_options jsonb) returns text
language plpgsql stable
as $$
declare
    v_ids uuid [];
    v_text text;
begin
    select array_agg(s.id) into v_ids
    from core.stream as s
    where
        s.agent = p_options ->> 'agent'
        and s.id::text like lower(p_arguments ->> 'session_id') || '%';

    if coalesce(cardinality(v_ids), 0) <> 1 then
        return format(
            'Сессия %s не найдена или неоднозначна. Список: list_sessions.',
            p_arguments ->> 'session_id'
        );
    end if;

    select string_agg(
        format(
            '%s: %s',
            case e.kind when 'user' then 'Пользователь' else 'Ассистент' end,
            e.payload ->> 'text'
        ),
        e'\n\n' order by e.id
    )
    into v_text
    from core.event as e
    where
        e.stream_id = v_ids[1]
        and e.kind in ('user', 'model')
        and e.payload ->> 'text' is not null;

    return coalesce(v_text, 'Сессия пуста.');
end
$$;
