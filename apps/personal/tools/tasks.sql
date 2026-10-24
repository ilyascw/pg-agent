-- Personal task list.

create function personal.add_task(
    p_arguments jsonb, p_options jsonb default '{}'
) returns text
language plpgsql
as $$
declare
    v_task personal.task;
begin
    insert into personal.task (title, due)
    values (p_arguments ->> 'title', (p_arguments ->> 'due')::date)
    returning * into v_task;

    return format('Задача #%s добавлена: %s', v_task.id, v_task.title)
        || coalesce(' (до ' || v_task.due || ')', '');
end
$$;

create function personal.list_tasks(
    p_arguments jsonb, p_options jsonb default '{}'
) returns text
language sql stable
as $$
    select coalesce(
        string_agg(
            format('#%s [%s] %s', t.id, case when t.done then 'x' else ' ' end, t.title)
            || coalesce(' — до ' || t.due, ''),
            e'\n' order by t.id
        ),
        'Задач нет.'
    )
    from personal.task as t
    where coalesce((p_arguments ->> 'include_done')::boolean, false) or not t.done
$$;

create function personal.complete_task(
    p_arguments jsonb, p_options jsonb default '{}'
) returns text
language plpgsql
as $$
declare
    v_task personal.task;
begin
    update personal.task
    set done = true
    where id = (p_arguments ->> 'task_id')::int
    returning * into v_task;

    if not found then
        return format('Задача #%s не найдена.', p_arguments ->> 'task_id');
    end if;
    return format('Задача #%s закрыта: %s', v_task.id, v_task.title);
end
$$;
