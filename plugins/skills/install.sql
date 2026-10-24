-- Skill libraries: catalog policy and load/list/save tools.
-- Included inside the caller's transaction; needs the core. Several apps may include
-- it, so it installs only once.

select to_regnamespace('skills') is null as plugin_missing \gset
\if :plugin_missing
\ir skills.sql
\endif
