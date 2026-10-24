-- Skills: Markdown playbooks the agent loads for complex tasks and can write itself.

create function personal.list_skills(
    p_arguments jsonb, p_options jsonb default '{}'
) returns text
language sql stable
as $$
    select coalesce(
        'Доступные скиллы: ' || string_agg(s.name, ', ' order by s.name),
        'Скиллов нет.'
    )
    from personal.skill as s
$$;

create function personal.load_skill(
    p_arguments jsonb, p_options jsonb default '{}'
) returns text
language sql stable
as $$
    select coalesce(
        (select s.content from personal.skill as s where s.name = lower(trim(p_arguments ->> 'name'))),
        format('Скилл «%s» не найден. %s', p_arguments ->> 'name', personal.list_skills('{}'))
    )
$$;

create function personal.save_skill(
    p_arguments jsonb, p_options jsonb default '{}'
) returns text
language plpgsql
as $$
declare
    v_name text := replace(replace(lower(trim(p_arguments ->> 'name')), ' ', '_'), '-', '_');
    v_content text := trim(p_arguments ->> 'content');
    v_existed boolean;
begin
    if v_name !~ '^[a-z0-9]+(_[a-z0-9]+)*$' then
        return 'Имя скилла — только латиница, цифры и подчёркивания. Например: meeting_notes';
    end if;
    if length(v_content) < 200 then
        return 'Слишком короткая методичка. Скилл должен объяснять, когда применяться, '
            || 'в каком порядке работать, что проверить и как оформить ответ.';
    end if;

    v_existed := exists (select from personal.skill where name = v_name);
    insert into personal.skill (name, content) values (v_name, v_content)
    on conflict (name) do update set content = excluded.content, updated_at = now();

    return format(
        'Скилл «%s» %s. Загружай его через load_skill("%s").',
        v_name, case when v_existed then 'обновлён' else 'создан' end, v_name
    );
end
$$;
