begin;

select plan(13);

select is(mcp.tool_name('vv', 'vv_search'), 'vv_search', 'server prefix is not doubled');
select is(mcp.tool_name('vv', 'Get-Item.v2'), 'vv_get_item_v2', 'names are normalised');

select is(
    mcp.parse_response(
        'text/event-stream',
        e'event: message\r\ndata: {"jsonrpc": "2.0", "method": "notice"}\r\n\r\n'
        || e'event: message\r\ndata: {"jsonrpc": "2.0",\r\ndata:  "id": 7, "result": {}}\r\n\r\n',
        7
    ),
    '{"jsonrpc": "2.0", "id": 7, "result": {}}',
    'sse: multi-line data, other messages skipped'
);

select is(
    mcp.parse_response('application/json', '[{"id": 1}, {"id": 2, "result": 2}]', 2),
    '{"id": 2, "result": 2}',
    'json batch'
);

-- A fake server in place of the network call; rolled back with the test.
create table pg_temp.calls (method text, session_id text);

create or replace function mcp.post(p_server mcp.server, p_message jsonb)
returns public.http_response
language plpgsql
as $$
declare
    v_result jsonb;
    v_session text := 's' || (select count(*) + 1 from pg_temp.calls where method = 'initialize');
begin
    insert into pg_temp.calls values (p_message ->> 'method', p_server.session_id);

    if p_message ->> 'method' = 'tools/call' and p_server.session_id = 's1' then
        return row(404, 'text/plain', '{}', 'session expired')::public.http_response;
    end if;

    v_result := case p_message ->> 'method'
        when 'initialize' then '{"protocolVersion": "2025-06-18"}'::jsonb
        when 'tools/list' then case
            when p_message -> 'params' ? 'cursor' then
                '{"tools": [{"name": "vv_secret", "inputSchema": {"type": "object"}}]}'::jsonb
            else '{"nextCursor": "p2", "tools": [
                {"name": "vv_search", "description": "Search", "inputSchema": {
                    "type": "object", "properties": {"q": {"type": "string"}}, "required": ["q"]}},
                {"name": "vv_boom"}
            ]}'::jsonb
        end
        when 'tools/call' then case p_message -> 'params' ->> 'name'
            when 'vv_search' then jsonb_build_object('content', jsonb_build_array(
                jsonb_build_object('type', 'text', 'text', 'found ' || (p_message -> 'params' -> 'arguments' ->> 'q')),
                jsonb_build_object('type', 'image', 'data', '...')
            ))
            else '{"isError": true, "content": [{"type": "text", "text": "kaboom"}]}'::jsonb
        end
    end;

    if p_message ? 'id' then
        return row(
            200,
            'text/event-stream',
            array[public.http_header('Mcp-Session-Id', v_session)],
            format(e'event: message\ndata: %s\n\n', jsonb_build_object('jsonrpc', '2.0', 'id', p_message -> 'id', 'result', v_result))
        )::public.http_response;
    end if;
    return row(202, null, '{}', '')::public.http_response;
end
$$;

select test.agent();

insert into mcp.server (name, url, exclude) values ('vv', 'http://fake', '{vv_secret}');

select is(mcp.sync('vv'), 2, 'tools from every page are imported, excluded ones skipped');

select is(
    (select array_agg(method order by method) from pg_temp.calls),
    array['initialize', 'notifications/initialized', 'tools/list', 'tools/list'],
    'client initialises before the first request'
);

select is(
    (
        select parameters ->> 'type' from tools.tool
        where name = 'vv_boom'
    ),
    'object',
    'schemas without type become objects'
);

select mcp.grant('vv', 'tester');

select is(
    tools.execute('tester', '{"id": "c", "name": "vv_search", "arguments": {"q": "milk"}}')
    ->> 'content',
    e'found milk\n[image]',
    'call goes through mcp; non-text content is named'
);

select is(
    (
        select array_agg(session_id) from pg_temp.calls
        where method = 'tools/call'
    ),
    array['s1', 's2'],
    'expired session is reinitialised and the call retried'
);

select is(
    tools.execute('tester', '{"id": "c", "name": "vv_boom", "arguments": {}}'),
    '{"call_id": "c", "name": "vv_boom", "content": "kaboom", "is_error": true}',
    'mcp tool errors become error results'
);

select is(
    tools.execute('tester', '{"id": "c", "name": "vv_search", "arguments": {}}') ->> 'content',
    'missing required arguments: q',
    'imported schemas are enforced'
);

insert into tools.tool (name, description, handler) values (
    'vv_mine', 'local', 'test.echo(jsonb, jsonb)'
);

create or replace function mcp.request(p_server text, p_method text, p_params jsonb default '{}')
returns jsonb
language sql
as $$
    select '{"tools": [{"name": "vv_search"}, {"name": "vv_mine"}]}'::jsonb
$$;

select is(mcp.sync('vv'), 1, 'tools the server dropped are removed');

select is(
    (
        select handler::text from tools.tool
        where name = 'vv_mine'
    ),
    'test.echo(jsonb,jsonb)',
    'a same-named local tool is not taken over'
);

select * from finish();

rollback;
