-- Registers the tools of the personal assistant. The agent row itself is created by
-- install.sql, which takes endpoint settings and the prompt from outside.

insert into tools.tool (name, description, parameters, handler, examples) values
(
    'current_datetime',
    'Текущие дата и время. Используй перед любыми рассуждениями про «сегодня».',
    default,
    'personal.current_datetime(jsonb, jsonb)',
    default
),
(
    'calculate',
    'Посчитать арифметическое выражение из чисел: + - * / ** и скобки. '
    || 'Считает точно, без ошибок округления. Только числа, без переменных и функций.',
    $${"type": "object", "required": ["expression"], "properties": {
        "expression": {"type": "string", "description": "Арифметическое выражение, например (2026-1990)*12"}
    }}$$,
    'personal.calculate(jsonb, jsonb)',
    $$[{"request": "посчитай сложный процент: 100000 под 12% на 5 лет",
        "params": {"expression": "100000 * 1.12 ** 5"}}]$$
),
(
    'add_task',
    'Добавить задачу в личный список дел.',
    $${"type": "object", "required": ["title"], "properties": {
        "title": {"type": "string", "description": "Что нужно сделать"},
        "due": {"type": "string", "description": "Срок в формате ГГГГ-ММ-ДД, если есть"}
    }}$$,
    'personal.add_task(jsonb, jsonb)',
    $$[{"request": "напомни завтра оплатить интернет", "params": {"title": "оплатить интернет"}}]$$
),
(
    'list_tasks',
    'Показать список задач пользователя.',
    $${"type": "object", "properties": {
        "include_done": {"type": "boolean", "description": "Показывать ли выполненные"}
    }}$$,
    'personal.list_tasks(jsonb, jsonb)',
    default
),
(
    'complete_task',
    'Отметить задачу выполненной.',
    $${"type": "object", "required": ["task_id"], "properties": {
        "task_id": {"type": "integer", "description": "Номер задачи из списка"}
    }}$$,
    'personal.complete_task(jsonb, jsonb)',
    default
),
(
    'save_note',
    'Записать факт в личную память пользователя (заметки, факты, записи). '
    || 'Зови, когда просят «запомни», «запиши», «сохрани» или сообщают личный факт, '
    || 'который пригодится позже.',
    $${"type": "object", "required": ["text"], "properties": {
        "text": {"type": "string", "description": "Текст заметки"},
        "tags": {"type": "string", "description": "Теги через запятую"}
    }}$$,
    'personal.save_note(jsonb, jsonb)',
    $$[{
        "request": "запомни: Семчик — ореховый магнат",
        "params": {"text": "Семчик — ореховый магнат"}
    }]$$
),
(
    'search_notes',
    'Найти в личной памяти пользователя: заметки, факты, записи, «что я писал». '
    || 'Зови всегда, когда в запросе есть «мои», «в фактах», «в заметках», «в памяти», '
    || '«я записывал», «я говорил» — до любых рассуждений по общим знаниям. '
    || 'Ищи по одному ключевому слову, а не по фразе целиком. Если пусто, попробуй '
    || 'другое ключевое слово из запроса, прежде чем сказать «не нашлось».',
    $${"type": "object", "required": ["query"], "properties": {
        "query": {"type": "string", "description": "ОДНО ключевое слово: имя, тема или тег. Не фраза, не вопрос"}
    }}$$,
    'personal.search_notes(jsonb, jsonb)',
    $$[
        {"request": "что я писал про отпуск", "params": {"query": "отпуск"}},
        {"request": "поищи семчика в фактах", "params": {"query": "семчик"}},
        {"request": "у себя в памяти посмотри про ипотеку", "params": {"query": "ипотека"}},
        {"request": "кто такой Кузя, глянь мои заметки", "params": {"query": "кузя"}}
    ]$$
),
(
    'get_weather',
    'Текущая погода в городе.',
    $${"type": "object", "required": ["city"], "properties": {
        "city": {"type": "string", "description": "Название города, например Москва"}
    }}$$,
    'personal.get_weather(jsonb, jsonb)',
    $$[{"request": "погода в питере", "params": {"city": "Санкт-Петербург"}}]$$
),
(
    'get_currency_rate',
    'Официальный курс валюты ЦБ РФ к рублю.',
    $${"type": "object", "properties": {
        "code": {"type": "string", "description": "Код валюты по ЦБ РФ: USD, EUR, CNY"}
    }}$$,
    'personal.get_currency_rate(jsonb, jsonb)',
    $$[{"request": "почём юань", "params": {"code": "CNY"}}]$$
),
(
    'list_skills',
    'Показать доступные скиллы — методички для сложных задач.',
    default,
    'personal.list_skills(jsonb, jsonb)',
    default
),
(
    'load_skill',
    'Загрузить методичку по сложной задаче и дальше действовать строго по ней. '
    || 'financial_model — финмодели, юнит-экономика, окупаемость, кассовый разрыв: загружай '
    || 'ДО того, как считать. skill_authoring — как написать новый скилл.',
    $${"type": "object", "required": ["name"], "properties": {
        "name": {"type": "string", "description": "Имя скилла, например financial_model"}
    }}$$,
    'personal.load_skill(jsonb, jsonb)',
    $$[
        {"request": "построй финмодель кофейни", "params": {"name": "financial_model"}},
        {"request": "посчитай юнит-экономику доставки", "params": {"name": "financial_model"}}
    ]$$
),
(
    'save_skill',
    'Создать или обновить скилл — методичку, которой ты будешь пользоваться потом. '
    || 'Сначала загрузи load_skill("skill_authoring") и пиши строго по его формату. '
    || 'Скилл с тем же именем перезаписывается, поэтому сперва прочитай его через load_skill.',
    $${"type": "object", "required": ["name", "content"], "properties": {
        "name": {"type": "string", "description": "Имя латиницей через подчёркивание, например meeting_notes"},
        "content": {"type": "string", "description": "Готовый текст методички в Markdown"}
    }}$$,
    'personal.save_skill(jsonb, jsonb)',
    default
);

-- Core session tools, scoped to this agent's streams by options.
insert into tools.tool (name, description, parameters, handler, options) values
(
    'list_sessions',
    'Прошлые диалоги с пользователем: короткий id, дата и первое сообщение, новые сверху. '
    || 'Зови, когда спрашивают «что мы обсуждали», «в прошлый раз», «я тебя уже спрашивал».',
    $${"type": "object", "properties": {
        "limit": {"type": "integer", "description": "Сколько последних сессий показать, по умолчанию 10"}
    }}$$,
    'tools.list_sessions(jsonb, jsonb)',
    '{"agent": "personal"}'
),
(
    'read_session',
    'Текст прошлого диалога: реплики пользователя и твои ответы, без вызовов инструментов. '
    || 'id бери из list_sessions.',
    $${"type": "object", "required": ["session_id"], "properties": {
        "session_id": {"type": "string", "description": "id сессии или его начало, например 1a2b3c4d"}
    }}$$,
    'tools.read_session(jsonb, jsonb)',
    '{"agent": "personal"}'
);

-- Grants every personal tool to an agent and attaches the standard policies.
create function personal.equip(p_agent text, p_stop_hint text) returns void
language sql
as $$
    insert into tools.agent_tool (agent, tool)
    select p_agent, t.name
    from tools.tool as t
    where t.handler::text like 'personal.%' or t.options ->> 'agent' = p_agent;

    insert into ctx.policy (agent, position, fn, options)
    values (p_agent, 1, 'ctx.last_turns(jsonb, jsonb)', '{"turns": 30}');

    insert into mw.middleware (agent, hook, position, fn, options) values
    (
        p_agent, 'before_llm', 1, 'mw.loop_guard(jsonb, jsonb)',
        jsonb_build_object('max_tool_steps', 8, 'max_same_call', 2, 'hint', p_stop_hint)
    ),
    (p_agent, 'after_llm', 1, 'mw.drop_empty_arguments(jsonb, jsonb)', '{}');
$$;
