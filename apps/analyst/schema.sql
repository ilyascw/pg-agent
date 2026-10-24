-- Text-to-SQL analyst: run_sql executes the model's query in a separate session of
-- analyst_reader, a role that can only read the dataset schemas each dataset install
-- grants it.

-- Roles are cluster-wide, so another database may have created it already. It logs
-- in without a password through the local socket only (trust in the image's
-- pg_hba.conf); TCP connections require a password it does not have.
do $$
begin
    if not exists (select from pg_roles where rolname = 'analyst_reader') then
        create role analyst_reader login;
    end if;
end
$$;

-- Functions are executable by everyone by default, and pgsql-http lives in public:
-- without this a query could make HTTP requests, for example when text in the data
-- talks the model into it. The agent itself runs as the owner and is not affected.
revoke execute on all functions in schema public from public;

create schema analyst;

comment on schema analyst is 'Text-to-SQL analyst: read-only query tool over dataset schemas.';

create extension dblink schema analyst;

-- dblink included: only the agent calls these.
revoke execute on all functions in schema analyst from public;

-- Rows of a json array as a Markdown table, at most p_limit of them.
create function analyst.markdown_table(p_rows json, p_limit int) returns text
language sql immutable
as $$
    with
    columns as (
        select k.name, k.n
        from json_object_keys(p_rows -> 0) with ordinality as k (name, n)
    ),
    body as (
        select
            r.n,
            '| ' || string_agg(
                coalesce(
                    left(regexp_replace(r.row ->> c.name, '[|\n\r]+', ' ', 'g'), 80), ''
                ),
                ' | ' order by c.n
            ) || ' |' as line
        from json_array_elements(p_rows) with ordinality as r (row, n)
        cross join columns as c
        where r.n <= p_limit
        group by r.n
    )
    select concat_ws(
        e'\n',
        '| ' || (select string_agg(c.name, ' | ' order by c.n) from columns as c) || ' |',
        '|' || (select string_agg(' --- |', '' order by c.n) from columns as c),
        (select string_agg(b.line, e'\n' order by b.n) from body as b)
    )
$$;

-- Tool handler. statement_timeout cannot stop a query inside a running turn, so the
-- query runs in its own read-only session of analyst_reader, and the deadline is kept
-- here: the query text could switch the remote timeout off, but not this loop. The
-- query is wrapped as a subquery to cap the rows. Planner cost estimates do not work
-- as a guard: joins of per-key aggregates, the right way to combine olist tables, are
-- overestimated a hundredfold.
-- options: {"max_rows": int, "timeout_s": number}
create function analyst.run_sql(p_arguments jsonb, p_options jsonb) returns text
language plpgsql
as $$
declare
    v_sql text := rtrim(btrim(p_arguments ->> 'sql', e' \n\r\t'), '; ');
    v_max_rows int := coalesce((p_options ->> 'max_rows')::int, 50);
    v_timeout interval := make_interval(secs => coalesce((p_options ->> 'timeout_s')::numeric, 15));
    v_deadline timestamptz;
    v_rows json;
    v_count int;
begin
    if v_sql is null or v_sql = '' then
        return 'Пустой запрос.';
    end if;

    if 'analyst_run' = any(coalesce(analyst.dblink_get_connections(), '{}')) then
        perform analyst.dblink_disconnect('analyst_run');
    end if;
    perform analyst.dblink_connect(
        'analyst_run',
        format(
            'dbname=%s user=analyst_reader options=''-c default_transaction_read_only=on''',
            current_database()
        )
    );
    begin
        perform analyst.dblink_send_query(
            'analyst_run',
            format(
                'select json_agg(t)::text from (select * from (%s) as q limit %s) as t',
                v_sql, v_max_rows + 1
            )
        );
        v_deadline := clock_timestamp() + v_timeout;
        while analyst.dblink_is_busy('analyst_run') = 1 loop
            if clock_timestamp() > v_deadline then
                perform analyst.dblink_cancel_query('analyst_run');
                perform analyst.dblink_disconnect('analyst_run');
                return format(
                    'Запрос не уложился в %s с и отменён. Скорее всего, не хватает условия '
                    || 'соединения или фильтра: сначала агрегируй таблицы по ключу, потом '
                    || 'соединяй.',
                    trim_scale(extract(epoch from v_timeout))
                );
            end if;
            perform pg_sleep(0.02);
        end loop;
        select r.rows::json into v_rows
        from analyst.dblink_get_result('analyst_run') as r (rows text);
        perform analyst.dblink_disconnect('analyst_run');
    exception when others then
        perform analyst.dblink_disconnect('analyst_run');
        raise;
    end;

    v_count := coalesce(json_array_length(v_rows), 0);
    if v_count = 0 then
        return 'Запрос вернул 0 строк.';
    end if;
    return analyst.markdown_table(v_rows, v_max_rows) || e'\n\n' || case
        when v_count > v_max_rows then format(
            'Показаны первые %s строк, есть ещё. Агрегируй или добавь limit.', v_max_rows
        )
        else format('Строк: %s.', v_count)
    end;
end
$$;
