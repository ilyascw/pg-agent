begin;

select plan(5);

create function pg_temp.request(p_calls jsonb) returns jsonb
language sql
as $$
    select jsonb_build_object(
        'tool_choice', 'auto',
        'events', jsonb_build_array(
            jsonb_build_object('kind', 'user', 'text', 'old'),
            jsonb_build_object('kind', 'model', 'tool_calls', '[{"name": "x", "arguments": {}}, {"name": "x", "arguments": {}}]'::jsonb),
            jsonb_build_object('kind', 'user', 'text', 'now')
        ) || (
            select coalesce(jsonb_agg(jsonb_build_object('kind', 'model', 'tool_calls', jsonb_build_array(c.call))), '[]')
            from jsonb_array_elements(p_calls) as c (call)
        )
    )
$$;

select is(
    mw.loop_guard(
        pg_temp.request('[{"name": "a", "arguments": {}}, {"name": "b", "arguments": {}}]'), '{}'
    )
    ->> 'tool_choice',
    'auto',
    'different calls in the current turn pass; previous turns do not count'
);

select is(
    mw.loop_guard(
        pg_temp.request(
            '[{"name": "a", "arguments": {"q": 1}}, {"name": "a", "arguments": {"q": 1}}]'
        ),
        '{}'
    )
    ->> 'tool_choice',
    'none',
    'repeating call stops tools'
);

select is(
    mw.loop_guard(
        pg_temp.request(
            $$[
                {"name": "a", "arguments": {}},
                {"name": "b", "arguments": {}},
                {"name": "c", "arguments": {}}
            ]$$
        ),
        '{"max_tool_steps": 3, "hint": "answer now"}'
    ) -> 'events' -> -1,
    '{"kind": "user", "text": "answer now"}',
    'too many steps stops tools and adds the hint'
);

select is(
    mw.drop_empty_arguments(
        $${"text": null, "tool_calls": [
            {"id": "c", "name": "n", "arguments": {"a": "", "b": "x", "c": 0}}
        ]}$$,
        '{}'
    ),
    '{"text": null, "tool_calls": [{"id": "c", "name": "n", "arguments": {"b": "x", "c": 0}}]}',
    'empty string arguments are dropped'
);

select is(
    mw.drop_empty_arguments('{"text": "hi", "tool_calls": []}', '{}'),
    '{"text": "hi", "tool_calls": []}',
    'answer without calls is untouched'
);

select * from finish();

rollback;
