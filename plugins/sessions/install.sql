-- Tools that let an agent read its own past conversations.
-- Included inside the caller's transaction; needs the core. Several apps may include
-- it, so it installs only once.

select to_regprocedure('tools.list_sessions(jsonb, jsonb)') is null as plugin_missing \gset
\if :plugin_missing
\ir sessions.sql
\endif
