-- Installs the text-to-SQL analyst and the plugins it uses on top of the core.
-- Datasets are installed separately from datasets/<name>/install.sql, since they need
-- the downloaded data (make analyst does both).
--
-- psql variables: base_url, api_key, model, tool_examples_field (empty to skip).
-- Prompt paths are relative to the repository root.
\set ON_ERROR_STOP on

\set prompt `cat apps/analyst/prompts/analyst.md`
\set stop_hint `cat apps/analyst/prompts/tool_limit.md`

begin;

\ir ../../plugins/builtin/install.sql
\ir ../../plugins/llm_openai/install.sql
\ir ../../plugins/skills/install.sql

\ir schema.sql
\ir agent.sql

-- The personal assistant may have registered the same endpoint already.
insert into llm.provider (name, adapter, config)
values (
    'openai',
    'llm_openai.complete(jsonb, jsonb)',
    jsonb_strip_nulls(jsonb_build_object(
        'base_url', :'base_url',
        'api_key', :'api_key',
        'tool_examples_field', nullif(:'tool_examples_field', '')
    ))
)
on conflict (name) do nothing;

insert into runtime.agent (name, provider, model, prompt)
values ('analyst', 'openai', :'model', :'prompt');

select analyst.equip('analyst', :'stop_hint');

commit;
