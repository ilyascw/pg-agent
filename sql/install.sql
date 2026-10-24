-- Installs the agent core. Order follows dependencies between layers.
\set ON_ERROR_STOP on

begin;

\ir core/plugin.sql
\ir llm/provider.sql
\ir runtime/agent.sql
\ir core/events.sql
\ir llm/openai.sql
\ir llm/fake.sql
\ir tools/registry.sql
\ir tools/sessions.sql
\ir mcp/client.sql
\ir ctx/assemble.sql
\ir ctx/policies.sql
\ir mw/middleware.sql
\ir mw/builtin.sql
\ir runtime/loop.sql

commit;
