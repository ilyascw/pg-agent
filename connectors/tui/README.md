# pg-agent TUI

Терминальный чат с агентом из pg-agent.

Интерфейс на Textual поверх клиента из `clients/python`.

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
