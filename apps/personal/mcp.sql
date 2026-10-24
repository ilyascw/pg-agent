-- MCP servers of the personal assistant. Needs the network, so it is applied by
-- make install and make mcp, not by tests. Only tools that work without
-- authorization are imported.

insert into mcp.server (name, url, exclude)
values (
    'vkusvill',
    'https://mcp.vkusvill.ru/mcp',
    -- These need the user's OAuth token.
    '{vkusvill_orders_history, vkusvill_product_lp, vkusvill_discounts_personal}'
)
on conflict (name) do update set url = excluded.url, exclude = excluded.exclude;

select mcp.sync('vkusvill');

select mcp.grant('vkusvill', 'personal');
