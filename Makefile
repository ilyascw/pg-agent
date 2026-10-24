-include .env
export

SQLFLUFF := uvx sqlfluff==4.4.0
PSQL := docker compose exec -T db psql -U agent -v ON_ERROR_STOP=1 -q
SCHEMAS := personal mcp runtime mw ctx tools llm_fake llm_openai llm core
APP_VARS = -v base_url="$$LLM_BASE_URL" -v api_key="$$LLM_API_KEY" -v model="$$LLM_MODEL" \
	-v tool_examples_field="$$LLM_TOOL_EXAMPLES_FIELD"

.PHONY: up down install mcp reset test lint fmt tui

up:
	docker compose up -d --build --wait

down:
	docker compose down

# Creates the core and the personal assistant in the "agent" database. Endpoint
# settings come from .env. Fails if it is already installed: use reset.
install:
	@test -n "$$LLM_BASE_URL" -a -n "$$LLM_MODEL" || { echo "Set LLM_BASE_URL and LLM_MODEL in .env"; exit 1; }
	$(PSQL) -d agent -f sql/install.sql
	$(PSQL) -d agent $(APP_VARS) -f apps/personal/install.sql
	$(MAKE) mcp

# Registers MCP servers and re-imports their tool lists.
mcp:
	$(PSQL) -d agent -f apps/personal/mcp.sql

# Drops every core schema with its data and installs it again.
reset:
	$(PSQL) -d agent -c "drop schema if exists $(shell echo $(SCHEMAS) | sed 's/ /, /g') cascade"
	$(MAKE) install

test:
	$(PSQL) -d postgres -c "drop database if exists agent_test" -c "create database agent_test"
	$(PSQL) -d agent_test -c "create extension pgtap" -c "create extension plpgsql_check"
	$(PSQL) -d agent_test -f sql/install.sql -f tests/fixtures.sql
	$(PSQL) -d agent_test -v base_url=http://llm.invalid -v api_key=0 -v model=test \
		-v tool_examples_field= -f apps/personal/install.sql
	docker compose exec -T db pg_prove -U agent -d agent_test tests/*_test.sql apps/*/tests/*_test.sql
	cd connectors/tui && uv run pytest -q

lint:
	$(SQLFLUFF) lint sql tests apps
	cd connectors/tui && uv run ruff check . && uv run ruff format --check .

fmt:
	-$(SQLFLUFF) fix sql tests apps
	cd connectors/tui && uv run ruff check --fix . && uv run ruff format .

tui:
	cd connectors/tui && uv run pg-agent-tui
