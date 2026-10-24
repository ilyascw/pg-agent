"""Integration tests run against the test database built by `make test` in the repository root."""

import os

import psycopg
import pytest

from pg_agent import AgentClient

DSN = os.environ.get("PG_AGENT_TEST_DSN", "postgresql://agent:agent@localhost:5433/agent_test")


@pytest.fixture
async def client() -> AgentClient:
    try:
        conn = await psycopg.AsyncConnection.connect(DSN, autocommit=True)
    except psycopg.OperationalError:
        pytest.skip("test database is not running; run `make up test` first")
    async with conn:
        await conn.execute("delete from runtime.agent where name = 'tester'")
        await conn.execute("delete from tools.tool where name in ('echo', 'fail')")
        await conn.execute("delete from llm.provider where name = 'fake'")
        await conn.execute("delete from llm_fake.reply")
        await conn.execute("select test.agent()")
        await conn.execute(
            "select llm_fake.script(llm_fake.call('echo', '{\"text\": \"ping\"}'),"
            " llm_fake.say('pong'))"
        )
    async with AgentClient(DSN, "tester") as agent:
        yield agent
