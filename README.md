# pg-agent

LLM-агент, который целиком живёт внутри Postgres. Цикл, инструменты, память и
вызовы модели написаны на PL/pgSQL. Никакого Python-сервиса между базой и моделью нет.

```sql
select runtime.open('personal');
call runtime.run(:stream, 'какой курс доллара?', null);
```

Это всё, что нужно клиенту. Дальше база сама собирает контекст, ходит в модель по HTTP,
выполняет инструменты и пишет каждый шаг в журнал.

## Почему это интересно

- **Программа — это данные.** Агент — строка в `runtime.agent`. Инструмент, политика
  контекста или middleware — строка в реестре со ссылкой на SQL-функцию. Новый агент
  создаётся через `insert`, деплоить ничего не нужно.
- **Транзакции бесплатно.** Упавший инструмент откатывается в подтранзакции вместе со
  всем, что успел записать, а модель получает ошибку текстом. Цикл продолжает работать.
- **Память — это таблица.** История диалога лежит в `core.event`. Её можно читать
  обычным `select`, в том числе самому агенту через инструмент `read_session`.
- **Стриминг без брокера.** Каждое событие отправляет `NOTIFY`, интерфейс слушает
  `LISTEN agent_events`.
- **Любой клиент.** Подключиться можно из чего угодно, что умеет говорить с Postgres:
  TUI, Telegram-бот или `psql`.

Слои устроены как в AG2: адаптер модели, цикл, инструменты, сборка контекста и
middleware отделены друг от друга узкими контрактами. Модель — любой
OpenAI-compatible эндпоинт Chat Completions.

## Быстрый старт

Нужен Docker. Остальное, включая `psql`, работает внутри контейнера.

```bash
cp .env.example .env   # указать LLM_BASE_URL и LLM_MODEL
make up                # Postgres 17 + http, plpgsql_check, pgTAP
make install           # ядро, плагины и личный ассистент в базе agent
make tui               # чат в терминале
```

Остальные команды — в разделе [Разработка](#разработка).

## Как это работает

### Всё состояние — таблицы

Агент не хранит ничего в памяти процесса. Всё, что определяет его поведение, и всё,
что он сделал, — строки в таблицах:

```text
llm.provider ◄── runtime.agent ──► core.stream ──► core.event
 (адаптер,         (модель,          (диалог)        (user / model / tool_result,
  base_url)         промпт)                           только дописываются)
                      │
        ┌─────────────┼──────────────────┐
        ▼             ▼                  ▼
 tools.agent_tool   ctx.policy      mw.middleware
        │           (как собрать     (что сделать до и
        ▼            контекст)        после вызова модели)
   tools.tool
 (имя, JSON Schema, функция-обработчик)
```

### Какие типы данных тут используются

В PL/pgSQL доступны все типы Postgres, а не только таблицы. В проекте работают такие:

**Строка таблицы — тоже тип.** Каждая таблица автоматически объявляет составной тип с
тем же именем. Поэтому в функции можно завести переменную-«структуру» и прочитать в
неё строку целиком:

```sql
declare
    v_agent runtime.agent;     -- поля name, provider, model, prompt, max_llm_calls
begin
    select a.* into v_agent from runtime.agent as a where ...;
    ... v_agent.model ...
```

Так устроены `runtime.step` (`runtime.agent`), `tools.execute` (`tools.tool`),
`ctx.assemble` (`ctx.policy`). Составной тип можно передать и параметром функции:
`mcp.post(p_server mcp.server, ...)`.

**`jsonb` — общий язык контрактов.** Запрос к модели, её ответ, события диалога,
состояние контекста, аргументы инструмента и `options` реестров — всё это `jsonb`.
Форма каждого документа описана комментарием в начале файла (например, в
`core/llm.sql`) и проверяется кодом: `check (jsonb_typeof(payload) = 'object')` в
таблицах, `llm.check_response` для ответа модели. Своих `create type` в проекте нет:
в `jsonb` плагин может добавить поле, не трогая схему ядра.

Операции над `jsonb`, которые чаще всего встречаются в коде:

| Выражение | Что делает |
| --- | --- |
| `x -> 'key'`, `x ->> 'key'` | поле как `jsonb` / как `text` |
| `x ? 'key'` | есть ли поле |
| `a \|\| b` | слить объекты или склеить массивы |
| `jsonb_build_object(...)`, `jsonb_agg(...)` | собрать объект / массив из строк запроса |
| `jsonb_array_elements(x) with ordinality` | развернуть массив в строки с номером |
| `jsonb_set(x, '{path}', v)` | заменить поле |

**`regprocedure` — указатель на функцию.** Это OID функции, который пишется и
читается как текст `'llm_openai.complete(jsonb, jsonb)'`. При вставке Postgres сам
проверяет, что такая функция существует. Колонки `adapter`, `handler`, `fn` в реестрах
имеют этот тип, а триггер `core.require_signature` дополнительно сверяет аргументы и
тип результата по `pg_proc`.

**Типы расширений.** `pgsql-http` приносит составные типы `http_request`,
`http_response`, `http_header` — через них адаптер ходит в модель
(`llm_openai.complete`), а инструменты — во внешние API (`personal.http_json`).

**Остальное — обычные скаляры:** `uuid` для id диалога, `bigint generated always as
identity` для событий (их порядок — порядок диалога), `timestamptz`, `text[]` для тегов
и списков, `interval` и `numeric` в `analyst.run_sql` и `personal.calculate`.

### Как вызывается функция из реестра

В SQL нельзя просто вызвать значение колонки как функцию, поэтому ядро собирает текст
вызова и выполняет его динамически:

```sql
-- core.call_sql('test.echo(jsonb, jsonb)'::regprocedure) → 'select test.echo($1, $2)'
execute core.call_sql(v_tool.handler) into v_content using p_call -> 'arguments', v_tool.options;
```

`core.call_sql` (`core/plugin.sql`) берёт схему, имя и число аргументов из `pg_proc`, а
`execute ... using` передаёт значения параметрами, а не вклеивает их в текст. Этим одним
механизмом вызываются адаптеры моделей, инструменты, политики и middleware.

### Один ход по шагам

Пользователь пишет «сколько будет 15% от 2400?» агенту `personal`.

1. `runtime.run` записывает событие `user` и делает `commit`.
2. `runtime.step` собирает запрос к модели:
   - `core.history(stream)` — все события диалога одним `jsonb`-массивом;
   - `ctx.assemble` — промпт агента плюс история, прогнанные через его политики
     (`ctx.last_turns` оставит последние 30 ходов);
   - `tools.schemas(agent)` — описания разрешённых агенту инструментов;
   - `mw.apply(..., 'before_llm', ...)` — например, `mw.loop_guard` запретит
     инструменты, если модель зациклилась.
3. `llm.complete` находит провайдера в `llm.provider` и вызывает его адаптер.
   `llm_openai` переводит нейтральный запрос в формат Chat Completions, делает HTTP POST
   и переводит ответ обратно.
4. Ответ проходит `after_llm` middleware и `llm.check_response`, затем пишется событием
   `model`.
5. Для каждого `tool_call` из ответа `tools.execute` проверяет доступ и обязательные
   аргументы, вызывает обработчик и пишет событие `tool_result`.
6. Если вызовов инструментов не было, ход закончен. Иначе — `commit` и снова шаг 2,
   но не больше `runtime.agent.max_llm_calls` раз.

В журнале после этого лежит (id вызова и текст ответа условные):

| kind | payload |
| --- | --- |
| `user` | `{"text": "сколько будет 15% от 2400?"}` |
| `model` | `{"text": null, "tool_calls": [{"id": "call_1", "name": "calculate", "arguments": {"expression": "2400 * 0.15"}}], "usage": {...}}` |
| `tool_result` | `{"call_id": "call_1", "name": "calculate", "content": "360", "is_error": false}` |
| `model` | `{"text": "15% от 2400 — это 360.", "tool_calls": [], "usage": {...}}` |
### Транзакции

- `runtime.run` — процедура, а не функция: только процедура может делать `commit`
  внутри себя. Поэтому её зовут через `call` и вне явной транзакции (клиент работает
  в autocommit). Каждый шаг закоммичен, и если вызов модели упадёт на пятом шаге,
  первые четыре останутся в журнале.
- `runtime.send` — тот же ход одной транзакцией. Удобно в тестах: можно откатить всё
  через `rollback`.
- Блок `begin ... exception when others then ... end` в `tools.execute` — это
  savepoint. Если обработчик что-то записал и упал, его записи откатываются, а модель
  получает `is_error: true` с текстом ошибки. HTTP-запрос, который инструмент уже
  отправил, откатить, конечно, нельзя.

### Стриминг

Триггер `event_notify` на `core.event` вызывает
`pg_notify('agent_events', '{"stream_id", "event_id", "kind"}')`. Postgres доставляет
уведомления слушателям в момент `commit`, поэтому коннектор видит шаги по мере того,
как `runtime.run` их коммитит. Клиент (`clients/python`) держит три соединения: одно
выполняет ход, второе слушает `LISTEN agent_events`, третье дочитывает событие по
`event_id`.

### Как ставится

Установка — это `psql`-скрипты, а не миграции:

- `\ir file.sql` подключает файл относительно текущего, так `core/install.sql` и
  `apps/*/install.sql` собирают всё в одну транзакцию;
- плагин ставится один раз: `select to_regnamespace('skills') is null as
  plugin_missing \gset` кладёт результат в переменную psql, а `\if :plugin_missing`
  пропускает уже установленный;
- настройки из `.env` приходят переменными psql (`-v model=...`) и подставляются как
  `:'model'`, промпт читается из файла: `` \set prompt `cat apps/personal/prompts/assistant.md` ``;
- скиллы читает сам сервер из `/work` (туда compose монтирует репозиторий) через
  `pg_read_file` в `skills.import`.

### Попробовать без модели

`make test` создаёт базу `agent_test` с плагином `llm_fake` — моделью, которая
отвечает по заранее заданному сценарию. В ней можно прогнать ход руками. Если агент
`tester` в базе уже есть, строку с `test.agent()` надо пропустить.

```bash
docker compose exec db psql -U agent -d agent_test
```

```sql
begin;
select test.agent();                                  -- агент tester с инструментами echo и fail
select llm_fake.script(
    llm_fake.call('echo', '{"text": "ping"}'),        -- 1-й ответ модели: вызови echo
    llm_fake.say('pong')                              -- 2-й ответ: финальный текст
);
select runtime.send(runtime.open('tester'), 'say ping');   -- → pong
select kind, payload from core.event order by id desc limit 4;
select request from llm_fake.reply order by id desc limit 1;  -- что «модель» получила на входе
rollback;
```

## Где что лежит

| Каталог | Что там |
| --- | --- |
| `core/` | ядро: контракты и цикл, без них агент не работает |
| `plugins/` | реализации контрактов ядра; приложение ставит только нужные |
| `apps/personal/` | личный ассистент: задачи, заметки, скиллы, погода, курс валют, калькулятор |
| `apps/analyst/` | text-to-SQL агент над датасетами Olist и Formula 1, знания о таблицах — в скиллах, см. [README](apps/analyst/README.md) |
| `clients/python/` | Python-клиент к контракту коннекторов |
| `connectors/tui/` | терминальный чат (Textual) поверх клиента |
| `connectors/telegram/` | Telegram-бот поверх клиента; связь чата с диалогом — в `telegram.chat` |
| `docker/` | образ Postgres 17 с `pgsql-http`, `plpgsql_check`, pgTAP |

Тесты лежат рядом с кодом, в `tests/` каждого каталога. Каждый плагин — папка с
`install.sql`; приложение подключает плагины из своего `install.sql`, повторное
подключение ничего не делает.

### Ядро

Строки идут в порядке установки из `core/install.sql`, он следует зависимостям между
слоями.

| Схема | Файл | Что делает |
| --- | --- | --- |
| `core` | `core/plugin.sql` | механизм плагинов: `core.require_signature` проверяет сигнатуру, `core.call_sql` вызывает функцию из реестра |
| `llm` | `core/llm.sql` | нейтральный контракт запроса и ответа модели, реестр провайдеров, `llm.complete` |
| `runtime` | `core/agent.sql` | таблица `runtime.agent` |
| `core` | `core/events.sql` | журнал диалогов (`stream`, `event`), `core.history`, `core.streams`, `NOTIFY agent_events` |
| `tools` | `core/tools.sql` | реестр инструментов, доступы агентов, `tools.execute` |
| `ctx` | `core/ctx.sql` | сборка контекста: цепочка политик над промптом и историей |
| `mw` | `core/mw.sql` | middleware вокруг вызова модели (`before_llm`, `after_llm`) |
| `runtime` | `core/runtime.sql` | цикл: `open`, `step`, `send`, `run` |

Один шаг цикла (`runtime.step`):

```text
core.history ─► ctx.assemble ─► mw before_llm ─► llm.complete ─► mw after_llm
                                                                     │
          core.append(tool_result) ◄─ tools.execute ◄─ core.append(model)
```

### Плагины

| Плагин | Что даёт |
| --- | --- |
| `llm_openai` | адаптер к любому OpenAI-compatible эндпоинту Chat Completions; маппинг (`body`, `parse`) отделён от HTTP-вызова и тестируется без сети |
| `llm_fake` | модель по сценарию, для тестов и демо |
| `builtin` | политики `ctx.last_turns`, `ctx.append_system`; middleware `mw.loop_guard` (защита от зацикливания из `PolicyTransport`) и `mw.drop_empty_arguments` (убирает пустые строки, которыми некоторые модели заполняют необязательные аргументы) |
| `mcp` | MCP-клиент поверх Streamable HTTP: `mcp.sync` импортирует инструменты сервера в обычный реестр с общим обработчиком `mcp.call_tool` |
| `sessions` | инструменты `list_sessions`, `read_session`: агент читает прошлые диалоги |
| `skills` | библиотеки скиллов: каталог в промпте, полный текст по запросу, импорт из `.md` |

### Приложение

Приложение — это схема со своими таблицами и обработчиками, строки в реестрах и
`install.sql`, который всё это ставит. На примере `apps/personal/`:

| Файл | Что там |
| --- | --- |
| `install.sql` | подключает плагины, создаёт провайдера и агента, вызывает `personal.equip`, импортирует скиллы |
| `schema.sql` | схема `personal` и её таблицы `task`, `note` |
| `tools/*.sql` | обработчики инструментов: время и калькулятор, задачи, заметки, погода и курс валют |
| `agent.sql` | строки `tools.tool` с описаниями и JSON Schema; `personal.equip` выдаёт агенту инструменты, политику и middleware |
| `mcp.sql` | MCP-сервер ВкусВилла; ставится отдельно, потому что нужна сеть |
| `prompts/` | системный промпт и подсказка, которую `loop_guard` подставит при зацикливании |
| `skills/` | методички в Markdown, описание — в front matter |

## Точки расширения

Любая точка расширения — это обычная SQL-функция, записанная в реестр как
`regprocedure`. Сигнатуру проверяет триггер реестра, поэтому функцию с неправильной
сигнатурой нельзя зарегистрировать. `options` берутся из строки реестра.

| Реестр | Сигнатура |
| --- | --- |
| `llm.provider.adapter` | `(config jsonb, request jsonb) returns jsonb` |
| `tools.tool.handler` | `(arguments jsonb, options jsonb) returns text` |
| `ctx.policy.fn` | `(state jsonb, options jsonb) returns jsonb` |
| `mw.middleware.fn` | `(value jsonb, options jsonb) returns jsonb` |

Ошибка в инструменте откатывается в подтранзакции и возвращается модели как
`is_error: true`, цикл при этом не падает.

### Свой инструмент

Обработчик, строка в реестре и доступ агенту:

```sql
create function personal.reverse(p_arguments jsonb, p_options jsonb) returns text
language sql immutable
as $$
    select reverse(p_arguments ->> 'text')
$$;

insert into tools.tool (name, description, parameters, handler) values (
    'reverse',
    'Перевернуть строку.',
    '{"type": "object", "required": ["text"], "properties": {"text": {"type": "string"}}}',
    'personal.reverse(jsonb, jsonb)'
);

insert into tools.agent_tool (agent, tool) values ('personal', 'reverse');
```

Со следующего шага модель увидит инструмент. Перезапускать ничего не нужно.

## Контракт для коннекторов

```sql
select runtime.open('personal');                  -- новый диалог, uuid
call runtime.run(:stream, 'привет', null);        -- ход; коммит после каждого шага
listen agent_events;                              -- {"stream_id", "event_id", "kind"}
select core.history(:stream);                     -- весь диалог
```

`runtime.send(stream, text)` выполняет тот же ход одной транзакцией. Это удобно для
тестов, но события коннекторы увидят только в конце хода.

## Разработка

```bash
make up       # Postgres 17 + http, plpgsql_check, pgTAP
make install  # ядро, плагины и личный ассистент в базе agent (make reset — снести и поставить заново)
make analyst  # text-to-SQL агент с датасетами (скачает их с Kaggle)
make tui      # чат (PG_AGENT_NAME=analyst — с аналитиком)
make telegram # Telegram-бот (нужны TELEGRAM_BOT_TOKEN и TELEGRAM_ALLOWED_USERS)
make test     # pgTAP на чистой базе agent_test, затем тесты клиента и коннектора
make lint     # sqlfluff и ruff
make fmt      # их автоисправления
```

`LLM_BASE_URL` указывается так, как эндпоинт виден из контейнера с базой: адрес на
хосте — это `host.docker.internal`.

`make test` заодно прогоняет `plpgsql_check` по всем функциям ядра: он ловит опечатки
в колонках, ошибки типов и неверно указанную категорию изменчивости. sqlfluff тела
`$$ ... $$` не разбирает, поэтому эти две проверки дополняют друг друга.
