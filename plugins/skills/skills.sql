-- Skills: Markdown playbooks grouped into libraries. The system prompt carries only a
-- catalog of names and one-line descriptions (ctx policy skills.catalog); the agent
-- loads a full skill with a tool when the task needs it.
-- Tool options: {"library": name} — which library the tool works with.

create schema skills;

comment on schema skills is 'Skill libraries: catalog in the prompt, content on demand.';

create table skills.skill (
    library text not null check (library ~ '^[a-z][a-z0-9_]*$'),
    name text not null check (name ~ '^[a-z0-9]+(_[a-z0-9]+)*$'),
    description text not null,
    content text not null,
    updated_at timestamptz not null default now(),
    primary key (library, name)
);

create function skills.catalog_text(p_library text) returns text
language sql stable
as $$
    select string_agg(format('- %s — %s', s.name, s.description), e'\n' order by s.name)
    from skills.skill as s
    where s.library = p_library
$$;

-- Ctx policy: appends the catalog to the system prompt.
-- options: {"library": name, "title": text before the list}
create function skills.catalog(p_state jsonb, p_options jsonb) returns jsonb
language sql stable
as $$
    select case
        when skills.catalog_text(p_options ->> 'library') is null then p_state
        else jsonb_set(
            p_state,
            '{system}',
            to_jsonb(concat_ws(
                e'\n\n',
                p_state ->> 'system',
                concat_ws(
                    e'\n', p_options ->> 'title', skills.catalog_text(p_options ->> 'library')
                )
            ))
        )
    end
$$;

create function skills.list(p_arguments jsonb, p_options jsonb) returns text
language sql stable
as $$
    select coalesce(
        e'Доступные скиллы:\n' || skills.catalog_text(p_options ->> 'library'),
        'Скиллов нет.'
    )
$$;

create function skills.load(p_arguments jsonb, p_options jsonb) returns text
language sql stable
as $$
    select coalesce(
        (
            select s.content
            from skills.skill as s
            where
                s.library = p_options ->> 'library'
                and s.name = lower(trim(p_arguments ->> 'name'))
        ),
        format(
            e'Скилл «%s» не найден. %s',
            p_arguments ->> 'name', skills.list('{}', p_options)
        )
    )
$$;

-- Lets the agent write its own skills. The description defaults to the first line of
-- the content without Markdown heading marks.
create function skills.save(p_arguments jsonb, p_options jsonb) returns text
language plpgsql
as $$
declare
    v_library text := p_options ->> 'library';
    v_name text := replace(replace(lower(trim(p_arguments ->> 'name')), ' ', '_'), '-', '_');
    v_content text := btrim(p_arguments ->> 'content', e' \n\r\t');
    v_existed boolean;
begin
    if v_name !~ '^[a-z0-9]+(_[a-z0-9]+)*$' then
        return 'Имя скилла — только латиница, цифры и подчёркивания. Например: meeting_notes';
    end if;
    if length(v_content) < 200 then
        return 'Слишком короткая методичка. Скилл должен объяснять, когда применяться, '
            || 'в каком порядке работать, что проверить и как оформить ответ.';
    end if;

    v_existed := exists (select from skills.skill where library = v_library and name = v_name);
    insert into skills.skill (library, name, description, content)
    values (
        v_library,
        v_name,
        coalesce(
            nullif(trim(p_arguments ->> 'description'), ''),
            trim(ltrim(split_part(v_content, e'\n', 1), '# '))
        ),
        v_content
    )
    on conflict (library, name) do update
    set description = excluded.description, content = excluded.content, updated_at = now();

    return format(
        'Скилл «%s» %s. Загружай его через load_skill("%s").',
        v_name, case when v_existed then 'обновлён' else 'создан' end, v_name
    );
end
$$;

-- Loads every *.md of a server-side directory into a library; the file name is the
-- skill name. A file starts with front matter that holds the description:
--   ---
--   description: one line for the catalog
--   ---
-- Reads files as the database server sees them, so it needs superuser or
-- pg_read_server_files. Returns how many skills were loaded.
create function skills.import(p_library text, p_dir text) returns int
language plpgsql
as $$
declare
    v_file text;
    v_parts text [];
    v_count int := 0;
begin
    for v_file in
        select f.name from pg_ls_dir(p_dir) as f (name) where f.name like '%.md' order by f.name
    loop
        v_parts := regexp_match(
            pg_read_file(p_dir || '/' || v_file),
            '^---\s*\ndescription:\s*([^\n]+)\n---\s*\n(.*)$'
        );
        if v_parts is null then
            raise exception 'skill %/% has no front matter with a description', p_dir, v_file;
        end if;
        insert into skills.skill (library, name, description, content)
        values (p_library, left(v_file, -3), btrim(v_parts[1]), btrim(v_parts[2], e' \n\r\t'))
        on conflict (library, name) do update
        set description = excluded.description, content = excluded.content, updated_at = now();
        v_count := v_count + 1;
    end loop;
    return v_count;
end
$$;
