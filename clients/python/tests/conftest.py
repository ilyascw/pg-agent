"""Integration tests run against the test database built by `make test` in the repository root."""

import psycopg
import pytest

from pg_agent import AgentClient
from pg_agent.testing import TEST_DSN, reset_tester

DSN = TEST_DSN


@pytest.fixture
async def client() -> AgentClient:
    try:
        await reset_tester()
    except psycopg.OperationalError:
        pytest.skip("test database is not running; run `make up test` first")
    async with AgentClient(DSN, "tester") as agent:
        yield agent
