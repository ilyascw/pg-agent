# pg-agent Telegram

Telegram-бот поверх клиента из `clients/python`. Каждый чат ведёт свою сессию агента;
какая сессия у какого чата, хранится в базе в таблице `telegram.chat`.

Пока агент работает, бот показывает «печатает…» и одно сообщение со списком вызванных
инструментов: ⏳ выполняется, ✅ готово, ❌ ошибка. Ответ модели в Markdown превращается
в форматирование Telegram, длинные ответы делятся на несколько сообщений.

<img src="../../docs/assets/telegram-recipe.png" alt="Бот ищет рецепт супа через MCP ВкусВилла" width="360">

## Запуск

1. Создать бота у [@BotFather](https://t.me/BotFather) и взять токен.
2. В `.env` в корне указать `TELEGRAM_BOT_TOKEN` и `TELEGRAM_ALLOWED_USERS`. Это id
   пользователей через запятую. Свой id бот покажет, если написать ему без доступа.
3. `make telegram` в корне: применяет `schema.sql` и запускает бота.

Без `TELEGRAM_ALLOWED_USERS` бот не запускается: агент видит заметки и задачи владельца.

| Переменная | По умолчанию |
| --- | --- |
| `TELEGRAM_BOT_TOKEN` | обязательна |
| `TELEGRAM_ALLOWED_USERS` | обязательна |
| `PG_AGENT_DSN` | `postgresql://agent:agent@localhost:5433/agent` |
| `PG_AGENT_NAME` | `personal` |

Команды: `/new`, `/sessions`, `/resume ID`, `/tools`, `/help`. Они же видны в меню бота.

Тесты (`uv run pytest`) ходят в базу `agent_test`, которую создаёт `make test` в корне.
