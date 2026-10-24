# pg-agent TUI

Терминальный чат с агентом из pg-agent.

- `src/pg_agent` — клиент к контракту ядра (`runtime.open`, `runtime.run`, `LISTEN
  agent_events`, `core.streams`). UI в нём нет, его используют и другие коннекторы.
- `src/pg_agent_tui` — интерфейс на Textual поверх клиента.

```bash
uv run pg-agent-tui
```

| Переменная | По умолчанию |
| --- | --- |
| `PG_AGENT_DSN` | `postgresql://agent:agent@localhost:5433/agent` |
| `PG_AGENT_NAME` | `personal` |
| `PG_AGENT_CONTEXT_WINDOW` | не задано; если задано, статус показывает долю окна контекста |

Команды: `/new`, `/sessions`, `/resume ID`, `/tools`, `/help`, `/quit`.

Тесты (`uv run pytest`) ходят в базу `agent_test`, которую создаёт `make test` в корне.
