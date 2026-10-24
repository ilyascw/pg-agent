-- Scripted model for tests and demos.
-- Included inside the caller's transaction; needs the core. Several apps may include
-- it, so it installs only once.

select to_regnamespace('llm_fake') is null as plugin_missing \gset
\if :plugin_missing
\ir fake.sql
\endif
