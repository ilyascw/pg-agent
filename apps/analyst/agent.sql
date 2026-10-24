-- Tools of the analyst and how an agent is equipped with them. The agent row itself
-- is created by install.sql, which takes endpoint settings and the prompt from outside.

insert into tools.tool (name, description, parameters, handler, options, examples) values
(
    'run_sql',
    'Выполнить один SELECT в PostgreSQL и получить результат таблицей (до 50 строк). '
    || 'Только чтение. Таблицы пиши со схемой: olist.orders, f1.races.',
    $${"type": "object", "required": ["sql"], "properties": {
        "sql": {"type": "string", "description": "Один запрос SELECT или WITH ... SELECT, без точки с запятой в середине"}
    }}$$,
    'analyst.run_sql(jsonb, jsonb)',
    '{"max_rows": 50, "timeout_s": 15}',
    $$[{
        "request": "сколько всего заказов",
        "params": {"sql": "select count(*) from olist.orders"}
    }]$$
),
(
    'load_table_skill',
    'Загрузить скилл таблицы: что в ней лежит, колонки, связи, подвохи и пример запроса. '
    || 'Зови перед первым запросом к таблице. Имена скиллов — в каталоге в системном промпте.',
    $${"type": "object", "required": ["name"], "properties": {
        "name": {"type": "string", "description": "Имя скилла из каталога, например olist_orders"}
    }}$$,
    'skills.load(jsonb, jsonb)',
    '{"library": "analyst"}',
    $$[{
        "request": "какие категории товаров продаются лучше",
        "params": {"name": "olist_order_items"}
    }]$$
);

-- Grants the analyst tools to an agent and attaches the skill catalog and guards.
create function analyst.equip(p_agent text, p_stop_hint text) returns void
language sql
as $$
    insert into tools.agent_tool (agent, tool) values
    (p_agent, 'run_sql'),
    (p_agent, 'load_table_skill');

    insert into ctx.policy (agent, position, fn, options) values
    (p_agent, 1, 'ctx.last_turns(jsonb, jsonb)', '{"turns": 20}'),
    (
        p_agent, 2, 'skills.catalog(jsonb, jsonb)',
        jsonb_build_object(
            'library', 'analyst',
            'title', 'Каталог таблиц (имя скилла — что в таблице):'
        )
    );

    insert into mw.middleware (agent, hook, position, fn, options) values
    (
        p_agent, 'before_llm', 1, 'mw.loop_guard(jsonb, jsonb)',
        jsonb_build_object('max_tool_steps', 12, 'max_same_call', 2, 'hint', p_stop_hint)
    ),
    (p_agent, 'after_llm', 1, 'mw.drop_empty_arguments(jsonb, jsonb)', '{}');
$$;
