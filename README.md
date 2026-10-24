# pg-agent

Ядро агента на PL/pgSQL. Устройство повторяет AG2: адаптер модели, цикл, инструменты,
сборка контекста и middleware — отдельные слои с узкими контрактами. Конкретный агент —
это строки в таблицах, а не код. Интерфейсы (TUI и другие) — отдельные коннекторы поверх
ядра. Модель — любой OpenAI-compatible эндпоинт Chat Completions.

| Каталог | Что там |
| --- | --- |
| `sql/` | ядро |
| `apps/personal/` | личный ассистент: задачи, заметки, скиллы, погода, курс валют, калькулятор |
| `connectors/tui/` | терминальный чат (Python, Textual) |

## Слои

| Схема | Файл | Что делает |
| --- | --- | --- |
| `core` | `sql/core/plugin.sql` | механизм плагинов: регистрация функций с проверкой сигнатуры и их вызов |
| `core` | `sql/core/events.sql` | журнал событий диалога (`stream`, `event`) и `NOTIFY agent_events` |
| `llm` | `sql/llm/provider.sql` | нейтральный контракт запроса и ответа модели, реестр провайдеров |
| `llm_openai` | `sql/llm/openai.sql` | адаптер к любому OpenAI-compatible эндпоинту Chat Completions |
| `llm_fake` | `sql/llm/fake.sql` | модель по сценарию, для тестов и демо |
| `tools` | `sql/tools/registry.sql` | реестр инструментов, доступы агентов, безопасное выполнение |
| `ctx` | `sql/ctx/*.sql` | сборка контекста: цепочка политик над промптом и историей |
| `mw` | `sql/mw/*.sql` | middleware вокруг вызова модели (`before_llm`, `after_llm`) |
| `runtime` | `sql/runtime/*.sql` | определение агента и цикл |

Один шаг цикла (`runtime.step`):

```text
core.history ─► ctx.assemble ─► mw before_llm ─► llm.complete ─► mw after_llm
                                                                     │
          core.append(tool_result) ◄─ tools.execute ◄─ core.append(model)
```

Шаги повторяются, пока модель не ответит без вызова инструментов.

## Плагины

Любая точка расширения — это обычная SQL-функция, записанная в реестр как
`regprocedure`. Сигнатуру проверяет триггер реестра, поэтому функцию с неправильной
сигнатурой нельзя зарегистрировать.

| Реестр | Сигнатура |
| --- | --- |
| `llm.provider.adapter` | `(config jsonb, request jsonb) returns jsonb` |
| `tools.tool.handler` | `(arguments jsonb) returns text` |
| `ctx.policy.fn` | `(state jsonb, options jsonb) returns jsonb` |
| `mw.middleware.fn` | `(value jsonb, options jsonb) returns jsonb` |

Встроенные плагины: `ctx.last_turns`, `ctx.append_system`, `mw.loop_guard` (защита
от зацикливания из `PolicyTransport`), `mw.drop_empty_arguments` (убирает пустые строки, которыми
некоторые модели заполняют необязательные аргументы).

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
make install  # ядро и личный ассистент в базе agent (make reset — снести и поставить заново)
make tui      # чат
make test     # pgTAP на чистой базе agent_test, затем тесты коннектора
make lint     # sqlfluff и ruff
make fmt      # их автоисправления
```

`LLM_BASE_URL` указывается так, как эндпоинт виден из контейнера с базой: адрес на
хосте — это `host.docker.internal`.

`make test` заодно прогоняет `plpgsql_check` по всем функциям ядра: он ловит опечатки
в колонках, ошибки типов и неверно указанную категорию изменчивости. sqlfluff тела
`$$ ... $$` не разбирает, поэтому эти две проверки дополняют друг друга.
