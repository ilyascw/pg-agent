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

## Структура

| Каталог | Что там |
| --- | --- |
| `core/` | ядро: контракты и цикл, без них агент не работает |
| `plugins/` | реализации контрактов ядра; приложение ставит только нужные |
| `apps/personal/` | личный ассистент: задачи, заметки, скиллы, погода, курс валют, калькулятор |
| `clients/python/` | Python-клиент к контракту коннекторов |
| `connectors/tui/` | терминальный чат (Textual) поверх клиента |
| `connectors/telegram/` | Telegram-бот поверх клиента |

Тесты лежат рядом с кодом, в `tests/` каждого каталога. Каждый плагин — папка с
`install.sql`; приложение подключает плагины из своего `install.sql`.

## Ядро

| Схема | Файл | Что делает |
| --- | --- | --- |
| `core` | `core/plugin.sql` | механизм плагинов: регистрация функций с проверкой сигнатуры и их вызов |
| `llm` | `core/llm.sql` | нейтральный контракт запроса и ответа модели, реестр провайдеров |
| `runtime` | `core/agent.sql` | определение агента |
| `core` | `core/events.sql` | журнал событий диалога (`stream`, `event`) и `NOTIFY agent_events` |
| `tools` | `core/tools.sql` | реестр инструментов, доступы агентов, безопасное выполнение |
| `ctx` | `core/ctx.sql` | сборка контекста: цепочка политик над промптом и историей |
| `mw` | `core/mw.sql` | middleware вокруг вызова модели (`before_llm`, `after_llm`) |
| `runtime` | `core/runtime.sql` | цикл |

Один шаг цикла (`runtime.step`):

```text
core.history ─► ctx.assemble ─► mw before_llm ─► llm.complete ─► mw after_llm
                                                                     │
          core.append(tool_result) ◄─ tools.execute ◄─ core.append(model)
```

Шаги повторяются, пока модель не ответит без вызова инструментов.

## Плагины

| Плагин | Что даёт |
| --- | --- |
| `llm_openai` | адаптер к любому OpenAI-compatible эндпоинту Chat Completions |
| `llm_fake` | модель по сценарию, для тестов и демо |
| `builtin` | политики `ctx.last_turns`, `ctx.append_system`; middleware `mw.loop_guard` (защита от зацикливания из `PolicyTransport`) и `mw.drop_empty_arguments` (убирает пустые строки, которыми некоторые модели заполняют необязательные аргументы) |
| `mcp` | MCP-клиент поверх Streamable HTTP: импортирует инструменты сервера в реестр |
| `sessions` | инструменты `list_sessions`, `read_session`: агент читает прошлые диалоги |

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

Нужен Docker. Остальное, включая `psql`, работает внутри контейнера.

```bash
cp .env.example .env   # указать LLM_BASE_URL и LLM_MODEL
make up       # Postgres 17 + http, plpgsql_check, pgTAP
make install  # ядро, плагины и личный ассистент в базе agent (make reset — снести и поставить заново)
make tui      # чат
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
