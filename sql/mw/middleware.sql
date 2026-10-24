-- Middleware: hooks around the model call. A middleware is
-- fn(value jsonb, options jsonb) returns jsonb, where value is the request for
-- before_llm and the response for after_llm. Hooks run in position order.

create schema mw;

comment on schema mw is 'Middleware around model calls.';

create table mw.middleware (
    agent text not null references runtime.agent on delete cascade,
    hook text not null check (hook in ('before_llm', 'after_llm')),
    position int not null,
    fn regprocedure not null,
    options jsonb not null default '{}' check (jsonb_typeof(options) = 'object'),
    primary key (agent, hook, position)
);

create trigger middleware_fn_signature
before insert or update of fn on mw.middleware
for each row execute function core.require_signature('fn', 'jsonb, jsonb', 'jsonb');

create function mw.apply(p_agent text, p_hook text, p_value jsonb) returns jsonb
language plpgsql
as $$
declare
    v_value jsonb := p_value;
    v_middleware mw.middleware;
begin
    for v_middleware in
        select * from mw.middleware where agent = p_agent and hook = p_hook order by position
    loop
        execute core.call_sql(v_middleware.fn) into v_value using v_value, v_middleware.options;
    end loop;
    return v_value;
end
$$;
