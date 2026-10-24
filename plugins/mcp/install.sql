-- MCP client over Streamable HTTP: imports server tools into the tool registry.
-- Included inside the caller's transaction; needs the core. Several apps may include
-- it, so it installs only once.

select to_regnamespace('mcp') is null as plugin_missing \gset
\if :plugin_missing
\ir client.sql
\endif
