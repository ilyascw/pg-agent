-- Adapter to any OpenAI-compatible Chat Completions endpoint.
-- Included inside the caller's transaction; needs the core. Several apps may include
-- it, so it installs only once.

select to_regnamespace('llm_openai') is null as plugin_missing \gset
\if :plugin_missing
\ir openai.sql
\endif
