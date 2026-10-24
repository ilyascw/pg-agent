"""Shared setup for connector integration tests.

They run against the ``agent_test`` database that ``make test`` builds in the repository
root, on the agent ``tester`` from ``core/tests/fixtures.sql``.
"""

from __future__ import annotations

import os

import psycopg

TEST_DSN = os.environ.get("PG_AGENT_TEST_DSN", "postgresql://agent:agent@localhost:5433/agent_test")


async def reset_tester(dsn: str = TEST_DSN) -> None:
    """Recreate the agent ``tester`` with a script: call echo("ping"), then answer "pong".

    Raises psycopg.OperationalError when the test database is not running.
    """
    async with await psycopg.AsyncConnection.connect(dsn, autocommit=True) as conn:
        await conn.execute("delete from runtime.agent where name = 'tester'")
        await conn.execute("delete from tools.tool where name in ('echo', 'fail')")
        await conn.execute("delete from llm.provider where name = 'fake'")
        await conn.execute("delete from llm_fake.reply")
        await conn.execute("select test.agent()")
        await conn.execute(
            "select llm_fake.script(llm_fake.call('echo', '{\"text\": \"ping\"}'),"
            " llm_fake.say('pong'))"
        )
