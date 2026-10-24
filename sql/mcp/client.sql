-- MCP client over Streamable HTTP. A server is a row; mcp.sync imports its tools into
-- the ordinary tool registry with one shared handler, mcp.call_tool, whose options name
-- the server and the tool. The agent loop never sees MCP.
--
-- Only POST is used: JSON-RPC requests whose responses come back as JSON or as an SSE
-- stream within the same HTTP response. Servers that keep a session get its id back in
-- Mcp-Session-Id; an expired session (HTTP 404) is reinitialised once.

create schema mcp;

comment on schema mcp is 'MCP client: servers and their tools as tool plugins.';

create table mcp.server (
    name text primary key check (name ~ '^[a-z][a-z0-9_]{0,31}$'),
    url text not null,
    -- Extra HTTP headers, e.g. {"Authorization": "Bearer ..."}.
    headers jsonb not null default '{}' check (jsonb_typeof(headers) = 'object'),
    -- Tool names not to import, e.g. tools that need authorization.
    exclude text[] not null default '{}',
    session_id text,
    protocol_version text
);

create sequence mcp.request_id;

-- Tool name in our registry: lower case, server prefix, at most 64 characters.
create function mcp.tool_name(p_server text, p_tool text) returns text
language sql immutable
as $$
    select left(
        case
            when lower(p_tool) like p_server || '\_%' then ''
            else p_server || '_'
        end || regexp_replace(lower(p_tool), '[^a-z0-9_]', '_', 'g'),
        64
    )
$$;

-- The JSON-RPC response with the given id from a JSON or SSE response body.
create function mcp.parse_response(p_content_type text, p_body text, p_id bigint)
returns jsonb
language plpgsql immutable
as $$
declare
    v_event text;
    v_message jsonb;
begin
    if p_content_type like 'text/event-stream%' then
        foreach v_event in array regexp_split_to_array(replace(p_body, e'\r', ''), e'\n\n') loop
            select string_agg(regexp_replace(line, '^data: ?', ''), e'\n')::jsonb
            into v_message
            from regexp_split_to_table(v_event, e'\n') as line
            where line like 'data:%';
            if v_message ->> 'id' = p_id::text then
                return v_message;
            end if;
        end loop;
    else
        v_message := p_body::jsonb;
        if jsonb_typeof(v_message) = 'array' then
            select m into v_message
            from jsonb_array_elements(v_message) as m
            where m ->> 'id' = p_id::text;
        end if;
        if v_message ->> 'id' = p_id::text then
            return v_message;
        end if;
    end if;
    raise exception 'mcp: no response with id % in %', p_id, left(p_body, 500);
end
$$;

-- The only function that talks to the network; tests replace it.
create function mcp.post(p_server mcp.server, p_message jsonb) returns public.http_response
language plpgsql
as $$
declare
    v_headers public.http_header [];
begin
    select array_agg(public.http_header(h.key, h.value))
    into v_headers
    from (
        select 'Accept' as key, 'application/json, text/event-stream' as value
        union all
        select 'Mcp-Session-Id', p_server.session_id where p_server.session_id is not null
        union all
        select 'MCP-Protocol-Version', p_server.protocol_version
        where p_server.protocol_version is not null
        union all
        select e.key, e.value from jsonb_each_text(p_server.headers) as e
    ) as h;

    perform public.http_set_curlopt('CURLOPT_CONNECTTIMEOUT', '10');
    perform public.http_set_curlopt('CURLOPT_TIMEOUT', '60');
    return public.http((
        'POST', p_server.url, v_headers, 'application/json', p_message::text
    )::public.http_request);
end
$$;

create function mcp.initialize(p_server text) returns void
language plpgsql
as $$
declare
    v_server mcp.server;
    v_id bigint := nextval('mcp.request_id');
    v_response public.http_response;
    v_result jsonb;
begin
    update mcp.server set session_id = null, protocol_version = null
    where name = p_server
    returning * into v_server;
    if not found then
        raise exception 'unknown mcp server: %', p_server;
    end if;

    v_response := mcp.post(v_server, jsonb_build_object(
        'jsonrpc', '2.0',
        'id', v_id,
        'method', 'initialize',
        'params', jsonb_build_object(
            'protocolVersion', '2025-06-18',
            'capabilities', '{}'::jsonb,
            'clientInfo', jsonb_build_object('name', 'pg-agent', 'version', '0.1')
        )
    ));
    if v_response.status <> 200 then
        raise exception 'mcp %: initialize failed: HTTP % %',
            p_server, v_response.status, left(v_response.content, 500);
    end if;
    v_result := mcp.parse_response(v_response.content_type, v_response.content, v_id);
    if v_result ? 'error' then
        raise exception 'mcp %: initialize failed: %', p_server, v_result -> 'error';
    end if;

    update mcp.server
    set
        protocol_version = v_result -> 'result' ->> 'protocolVersion',
        session_id = (
            select h.value from unnest(v_response.headers) as h
            where lower(h.field) = 'mcp-session-id'
        )
    where name = p_server
    returning * into v_server;

    perform mcp.post(v_server, '{"jsonrpc": "2.0", "method": "notifications/initialized"}');
end
$$;

-- Sends a request and returns its result; raises on transport and JSON-RPC errors.
create function mcp.request(p_server text, p_method text, p_params jsonb default '{}')
returns jsonb
language plpgsql
as $$
declare
    v_server mcp.server;
    v_id bigint;
    v_response public.http_response;
    v_message jsonb;
begin
    select * into v_server from mcp.server where name = p_server;
    if not found then
        raise exception 'unknown mcp server: %', p_server;
    end if;
    if v_server.protocol_version is null then
        perform mcp.initialize(p_server);
        select * into v_server from mcp.server where name = p_server;
    end if;

    for attempt in 1..2 loop
        v_id := nextval('mcp.request_id');
        v_response := mcp.post(v_server, jsonb_build_object(
            'jsonrpc', '2.0', 'id', v_id, 'method', p_method, 'params', p_params
        ));
        exit when not (v_response.status = 404 and v_server.session_id is not null and attempt = 1);
        perform mcp.initialize(p_server);
        select * into v_server from mcp.server where name = p_server;
    end loop;

    if v_response.status <> 200 then
        raise exception 'mcp %: % failed: HTTP % %',
            p_server, p_method, v_response.status, left(v_response.content, 500);
    end if;
    v_message := mcp.parse_response(v_response.content_type, v_response.content, v_id);
    if v_message ? 'error' then
        raise exception 'mcp %: % failed: %', p_server, p_method, v_message -> 'error' ->> 'message';
    end if;
    return v_message -> 'result';
end
$$;

-- Imports the server's tools into tools.tool and drops ones it no longer lists.
-- Returns the number of tools the server now has in the registry.
create function mcp.sync(p_server text) returns int
language plpgsql
as $$
declare
    v_exclude text [];
    v_tools jsonb := '[]'::jsonb;
    v_page jsonb;
    v_cursor text;
begin
    select exclude into v_exclude from mcp.server where name = p_server;
    if not found then
        raise exception 'unknown mcp server: %', p_server;
    end if;

    loop
        v_page := mcp.request(
            p_server,
            'tools/list',
            case when v_cursor is null then '{}' else jsonb_build_object('cursor', v_cursor) end
        );
        v_tools := v_tools || coalesce(v_page -> 'tools', '[]');
        v_cursor := v_page ->> 'nextCursor';
        exit when v_cursor is null;
    end loop;

    select coalesce(jsonb_agg(jsonb_build_object(
        'name', mcp.tool_name(p_server, t.tool ->> 'name'),
        'description', coalesce(t.tool ->> 'description', ''),
        'parameters', '{"type": "object"}'::jsonb || coalesce(t.tool -> 'inputSchema', '{}'),
        'options', jsonb_build_object('server', p_server, 'tool', t.tool ->> 'name')
    )), '[]')
    into v_tools
    from jsonb_array_elements(v_tools) as t (tool)
    where t.tool ->> 'name' <> all(v_exclude);

    delete from tools.tool as t
    where
        t.options ->> 'server' = p_server
        and t.name not in (select l.tool ->> 'name' from jsonb_array_elements(v_tools) as l (tool));

    insert into tools.tool (name, description, parameters, handler, options)
    select
        l.tool ->> 'name',
        l.tool ->> 'description',
        l.tool -> 'parameters',
        'mcp.call_tool(jsonb, jsonb)',
        l.tool -> 'options'
    from jsonb_array_elements(v_tools) as l (tool)
    -- A same-named tool from elsewhere is kept, and this one is not imported.
    on conflict (name) do update set
        description = excluded.description,
        parameters = excluded.parameters,
        handler = excluded.handler,
        options = excluded.options
    where tools.tool.options ->> 'server' = p_server;

    return (select count(*) from tools.tool as t where t.options ->> 'server' = p_server);
end
$$;

-- Gives an agent every imported tool of a server.
create function mcp.grant(p_server text, p_agent text) returns void
language sql
as $$
    insert into tools.agent_tool (agent, tool)
    select p_agent, t.name from tools.tool as t where t.options ->> 'server' = p_server
    on conflict do nothing
$$;

-- Tool handler for every imported tool. options: {"server", "tool"}
create function mcp.call_tool(p_arguments jsonb, p_options jsonb) returns text
language plpgsql
as $$
declare
    v_result jsonb := mcp.request(
        p_options ->> 'server',
        'tools/call',
        jsonb_build_object('name', p_options ->> 'tool', 'arguments', p_arguments)
    );
    v_text text;
begin
    select string_agg(
        case c.item ->> 'type'
            when 'text' then c.item ->> 'text'
            when 'resource' then coalesce(c.item -> 'resource' ->> 'text', c.item -> 'resource' ->> 'uri')
            else format('[%s]', c.item ->> 'type')
        end,
        e'\n'
        order by c.n
    )
    into v_text
    from jsonb_array_elements(coalesce(v_result -> 'content', '[]')) with ordinality as c (item, n);

    if (v_result ->> 'isError')::boolean then
        raise exception '%', coalesce(v_text, 'mcp tool failed');
    end if;
    return coalesce(v_text, v_result -> 'structuredContent' #>> '{}', '');
end
$$;
