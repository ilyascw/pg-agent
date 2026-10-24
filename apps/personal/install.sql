-- Installs the personal assistant on top of the core.
--
-- psql variables: base_url, api_key, model, tool_examples_field (empty to skip).
-- Paths of prompt and skill files are relative to the repository root.
\set ON_ERROR_STOP on

\set prompt `cat apps/personal/prompts/assistant.md`
\set stop_hint `cat apps/personal/prompts/tool_limit.md`
\set skill_financial_model `cat apps/personal/skills/financial_model.md`
\set skill_investor_call_prep `cat apps/personal/skills/investor_call_prep.md`
\set skill_skill_authoring `cat apps/personal/skills/skill_authoring.md`

begin;

\ir schema.sql
\ir tools/basic.sql
\ir tools/tasks.sql
\ir tools/notes.sql
\ir tools/skills.sql
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

insert into personal.skill (name, content) values
('financial_model', :'skill_financial_model'),
('investor_call_prep', :'skill_investor_call_prep'),
('skill_authoring', :'skill_skill_authoring');

commit;
