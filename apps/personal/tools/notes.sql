-- Personal memory: notes and facts.

create function personal.save_note(
    p_arguments jsonb, p_options jsonb default '{}'
) returns text
language plpgsql
as $$
begin
    insert into personal.note (text, tags)
    values (
        p_arguments ->> 'text',
        array(
            select trim(t.tag)
            from unnest(string_to_array(p_arguments ->> 'tags', ',')) as t (tag)
            where trim(t.tag) <> ''
        )
    );
    return format('Заметка сохранена (всего %s).', (select count(*) from personal.note));
end
$$;

-- Substring search over text and tags, newest first.
create function personal.search_notes(
    p_arguments jsonb, p_options jsonb default '{}'
) returns text
language sql stable
as $$
    with found as (
        select n.created_at, n.text
        from personal.note as n
        where
            strpos(lower(n.text), lower(p_arguments ->> 'query')) > 0
            or exists (
                select
                from unnest(n.tags) as t (tag)
                where strpos(lower(t.tag), lower(p_arguments ->> 'query')) > 0
            )
        order by n.created_at desc, n.id desc
        limit 10
    )

    select coalesce(
        string_agg(format('- %s: %s', found.created_at::date, found.text), e'\n'),
        'Ничего не нашлось.'
    )
    from found
$$;
