"""Terminal UI connector for pg-agent."""

import os

from .app import AgentApp

DEFAULT_DSN = "postgresql://agent:agent@localhost:5433/agent"


def main() -> None:
    AgentApp(
        dsn=os.environ.get("PG_AGENT_DSN", DEFAULT_DSN),
        agent=os.environ.get("PG_AGENT_NAME", "personal"),
    ).run()
