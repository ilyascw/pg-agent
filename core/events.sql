-- Event log. A stream is one conversation with one agent; events are appended and
-- never changed. Connectors LISTEN on channel agent_events to follow streams live:
-- notifications are delivered on commit, see runtime.run.

create table core.stream (
    id uuid primary key default gen_random_uuid(),
    agent text not null references runtime.agent on delete cascade,
    created_at timestamptz not null default now()
);

create table core.event (
    id bigint generated always as identity primary key,
    stream_id uuid not null references core.stream on delete cascade,
    kind text not null check (kind in ('user', 'model', 'tool_result')),
    payload jsonb not null check (jsonb_typeof(payload) = 'object'),
    created_at timestamptz not null default now()
);

create index event_stream_idx on core.event (stream_id, id);

create function core.open_stream(p_agent text) returns uuid
language sql
as $$
    insert into core.stream (agent) values (p_agent) returning id
$$;

create function core.append(p_stream uuid, p_kind text, p_payload jsonb) returns bigint
language sql
as $$
    insert into core.event (stream_id, kind, payload)
    values (p_stream, p_kind, p_payload)
    returning id
$$;

-- The stream as a list of provider-neutral events, see llm/provider.sql.
create function core.history(p_stream uuid) returns jsonb
language sql stable
as $$
    select coalesce(
        jsonb_agg(e.payload || jsonb_build_object('kind', e.kind) order by e.id),
        '[]'
    )
    from core.event as e
    where e.stream_id = p_stream
$$;

-- Latest streams of an agent with their first user message as a title.
create function core.streams(p_agent text, p_limit int default 20)
returns table (id uuid, created_at timestamptz, title text, events bigint)
language sql stable
as $$
    select
        s.id,
        s.created_at,
        (
            select e.payload ->> 'text'
            from core.event as e
            where e.stream_id = s.id and e.kind = 'user'
            order by e.id
            limit 1
        ),
        (select count(*) from core.event as e where e.stream_id = s.id)
    from core.stream as s
    where s.agent = p_agent
    order by s.created_at desc
    limit p_limit
$$;

create function core.notify_event() returns trigger
language plpgsql
as $$
begin
    perform pg_notify(
        'agent_events',
        json_build_object('stream_id', new.stream_id, 'event_id', new.id, 'kind', new.kind)::text
    );
    return null;
end
$$;

create trigger event_notify
after insert on core.event
for each row execute function core.notify_event();
