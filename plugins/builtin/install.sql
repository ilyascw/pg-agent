-- Stock context policies and middleware.
-- Included inside the caller's transaction; needs the core. Several apps may include
-- it, so it installs only once.

select to_regprocedure('ctx.last_turns(jsonb, jsonb)') is null as plugin_missing \gset
\if :plugin_missing
\ir ctx.sql
\ir mw.sql
\endif
