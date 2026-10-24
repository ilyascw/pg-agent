-- Agent definition: which model it talks to and with what prompt. Tools, context
-- policies and middleware attach to an agent in their own layers.

create schema runtime;

comment on schema runtime is 'Agent definitions and the agent loop.';

create table runtime.agent (
    name text primary key,
    provider text not null references llm.provider,
    model text not null,
    prompt text not null,
    -- Hard stop for one user turn; the loop guard middleware should stop tools earlier.
    max_llm_calls int not null default 10 check (max_llm_calls > 0)
);
