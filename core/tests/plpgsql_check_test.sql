begin;

select plan(1);

select is_empty(
    $$
        select p.oid::regprocedure::text, c.lineno, c.level, c.message
        from pg_proc as p
        inner join pg_namespace as n on p.pronamespace = n.oid
        inner join pg_language as l on p.prolang = l.oid
        cross join lateral plpgsql_check_function_tb(
            p.oid,
            case p.oid
                when 'core.require_signature()'::regprocedure then 'tools.tool'::regclass
                when 'core.notify_event()'::regprocedure then 'core.event'::regclass
                else 0
            end
        ) as c
        where
            l.lanname = 'plpgsql'
            and n.nspname in (
                'core', 'llm', 'llm_openai', 'llm_fake', 'tools', 'mcp', 'ctx', 'mw', 'runtime', 'personal'
            )
            -- Plugin signatures are fixed, so a plugin may ignore some of its parameters.
            and c.message not like 'unused parameter%'
    $$,
    'plpgsql_check reports nothing in core functions'
);

select * from finish();

rollback;
