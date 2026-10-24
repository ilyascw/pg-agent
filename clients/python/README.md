# pg-agent Python client

Клиент к контракту ядра: `runtime.open`, `runtime.run`, `LISTEN agent_events`,
`core.streams`. UI в нём нет, на нём строятся коннекторы из `connectors/`.

```python
async with AgentClient(dsn, "personal") as agent:
    stream = await agent.open()
    answer = await agent.run(stream, "привет")
```

Тесты (`uv run pytest`) ходят в базу `agent_test`, которую создаёт `make test` в корне.
