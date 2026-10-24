-- Context assembly: what the model sees on each call. It starts from the agent
-- prompt and the full stream history, then runs the agent's policies in order.
-- A policy is fn(state jsonb, options jsonb) returns jsonb, where
-- state = {"system": text, "events": [event]}. Policies never change the log.

create schema ctx;

comment on schema ctx is 'Context assembly policies.';

create table ctx.policy (
    agent text not null references runtime.agent on delete cascade,
    position int not null,
    fn regprocedure not null,
    options jsonb not null default '{}' check (jsonb_typeof(options) = 'object'),
    primary key (agent, position)
);

create trigger policy_fn_signature
before insert or update of fn on ctx.policy
for each row execute function core.require_signature('fn', 'jsonb, jsonb', 'jsonb');

create function ctx.assemble(p_agent text, p_events jsonb) returns jsonb
language plpgsql
as $$
declare
    v_state jsonb := jsonb_build_object(
        'system', (select a.prompt from runtime.agent as a where a.name = p_agent),
        'events', p_events
    );
    v_policy ctx.policy;
begin
    for v_policy in
        select * from ctx.policy where agent = p_agent order by position
    loop
        execute core.call_sql(v_policy.fn) into v_state using v_state, v_policy.options;
    end loop;
    return v_state;
end
$$;
