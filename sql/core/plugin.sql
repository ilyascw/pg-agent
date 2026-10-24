-- Plugins: every extension point (model adapter, tool, context policy, middleware)
-- is a plain SQL function stored as regprocedure in a registry table. The registry
-- declares the required signature with core.require_signature and calls the
-- function through core.call_sql.

create schema core;

comment on schema core is 'Plugin mechanism and the event log of conversations.';

create extension if not exists http with schema public;

-- Statement that calls p_fn with positional parameters $1..$n.
create function core.call_sql(p_fn regprocedure) returns text
language sql stable
as $$
    select format(
        'select %I.%I(%s)',
        n.nspname,
        p.proname,
        (select string_agg('$' || i, ', ') from generate_series(1, p.pronargs) as i)
    )
    from pg_proc as p
    inner join pg_namespace as n on p.pronamespace = n.oid
    where p.oid = p_fn
$$;

-- Trigger: tg_argv = (column, argument types, return type), as printed by
-- oidvectortypes and regtype, e.g. ('handler', 'jsonb', 'text').
create function core.require_signature() returns trigger
language plpgsql
as $$
declare
    v_fn regprocedure := (to_jsonb(new) ->> tg_argv[0])::regprocedure;
    v_args text;
    v_returns text;
begin
    select oidvectortypes(p.proargtypes), p.prorettype::regtype::text
    into v_args, v_returns
    from pg_proc as p
    where p.oid = v_fn;

    if v_args is distinct from tg_argv[1] or v_returns is distinct from tg_argv[2] then
        raise exception '%.%.%: % must be (%) returns %, got (%) returns %',
            tg_table_schema, tg_table_name, tg_argv[0], v_fn,
            tg_argv[1], tg_argv[2], v_args, v_returns;
    end if;
    return new;
end
$$;
