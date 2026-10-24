-- Installs the personal assistant and the plugins it uses on top of the core.
--
-- psql variables: base_url, api_key, model, tool_examples_field (empty to skip).
-- Prompt paths are relative to the repository root; skills are read by the server from
-- /work, where compose mounts the repository.
\set ON_ERROR_STOP on

\set prompt `cat apps/personal/prompts/assistant.md`
\set stop_hint `cat apps/personal/prompts/tool_limit.md`

begin;

\ir ../../plugins/builtin/install.sql
\ir ../../plugins/llm_openai/install.sql
\ir ../../plugins/mcp/install.sql
\ir ../../plugins/sessions/install.sql
\ir ../../plugins/skills/install.sql

\ir schema.sql
\ir tools/basic.sql
\ir tools/tasks.sql
\ir tools/notes.sql
\ir tools/external.sql
\ir agent.sql

insert into llm.provider (name, adapter, config)
values (
    'openai',
    'llm_openai.complete(jsonb, jsonb)',
    jsonb_strip_nulls(jsonb_build_object(
        'base_url', :'base_url',
        'api_key', :'api_key',
        'tool_examples_field', nullif(:'tool_examples_field', '')
    ))
);

insert into runtime.agent (name, provider, model, prompt)
values ('personal', 'openai', :'model', :'prompt');

select personal.equip('personal', :'stop_hint');

select skills.import('personal', '/work/apps/personal/skills');

commit;
