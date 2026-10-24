-- Installs the agent core. Order follows dependencies between layers.
\set ON_ERROR_STOP on

begin;

\ir plugin.sql
\ir llm.sql
\ir agent.sql
\ir events.sql
\ir tools.sql
\ir ctx.sql
\ir mw.sql
\ir runtime.sql

commit;
