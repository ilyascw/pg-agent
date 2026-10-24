-include .env
export

SQLFLUFF := uvx sqlfluff==4.4.0
PSQL := docker compose exec -T db psql -U agent -v ON_ERROR_STOP=1 -q
SCHEMAS := telegram analyst olist f1 personal skills mcp runtime mw ctx tools llm_fake llm_openai llm core
APP_VARS = -v base_url="$$LLM_BASE_URL" -v api_key="$$LLM_API_KEY" -v model="$$LLM_MODEL" \
	-v tool_examples_field="$$LLM_TOOL_EXAMPLES_FIELD"

.PHONY: up down install mcp analyst data reset test lint fmt tui telegram

up:
	docker compose up -d --build --wait

down:
	docker compose down

# Creates the core and the personal assistant with its plugins in the "agent" database. Endpoint
# settings come from .env. Fails if it is already installed: use reset.
install:
	@test -n "$$LLM_BASE_URL" -a -n "$$LLM_MODEL" || { echo "Set LLM_BASE_URL and LLM_MODEL in .env"; exit 1; }
	$(PSQL) -d agent -f core/install.sql
	$(PSQL) -d agent $(APP_VARS) -f apps/personal/install.sql
	$(MAKE) mcp

# Registers MCP servers and re-imports their tool lists.
mcp:
	$(PSQL) -d agent -f apps/personal/mcp.sql

# Downloads the analyst datasets from Kaggle into data/ (public, no login needed).
data: data/olist data/f1

data/olist:
	mkdir -p $@ && curl -fsSL -o $@/data.zip \
		https://www.kaggle.com/api/v1/datasets/download/olistbr/brazilian-ecommerce \
		&& unzip -oq $@/data.zip -d $@ && rm $@/data.zip

data/f1:
	mkdir -p $@ && curl -fsSL -o $@/data.zip \
		https://www.kaggle.com/api/v1/datasets/download/rohanrao/formula-1-world-championship-1950-2020 \
		&& unzip -oq $@/data.zip -d $@ && rm $@/data.zip

# Installs the text-to-SQL analyst with its datasets into the "agent" database.
analyst: data
	$(PSQL) -d agent $(APP_VARS) -f apps/analyst/install.sql
	$(PSQL) -d agent -f apps/analyst/datasets/olist/install.sql
	$(PSQL) -d agent -f apps/analyst/datasets/f1/install.sql

# Drops every core schema with its data and installs it again.
reset:
	$(PSQL) -d agent -c "drop schema if exists $(shell echo $(SCHEMAS) | sed 's/ /, /g') cascade"
	$(MAKE) install

test:
	$(PSQL) -d postgres -c "drop database if exists agent_test" -c "create database agent_test"
	$(PSQL) -d agent_test -c "create extension pgtap" -c "create extension plpgsql_check"
	$(PSQL) -d agent_test -f core/install.sql -f plugins/llm_fake/install.sql -f core/tests/fixtures.sql
	$(PSQL) -d agent_test -v base_url=http://llm.invalid -v api_key=0 -v model=test \
		-v tool_examples_field= -f apps/personal/install.sql
	$(PSQL) -d agent_test -v base_url=http://llm.invalid -v api_key=0 -v model=test \
		-v tool_examples_field= -f apps/analyst/install.sql
	$(PSQL) -d agent_test -f connectors/telegram/schema.sql
	docker compose exec -T db pg_prove -U agent -d agent_test \
		core/tests/*_test.sql plugins/*/tests/*_test.sql apps/*/tests/*_test.sql
	cd clients/python && uv run pytest -q
	cd connectors/tui && uv run pytest -q
	cd connectors/telegram && uv run pytest -q

lint:
	$(SQLFLUFF) lint core plugins apps connectors/telegram/schema.sql
	cd clients/python && uv run ruff check . && uv run ruff format --check .
	cd connectors/tui && uv run ruff check . && uv run ruff format --check .
	cd connectors/telegram && uv run ruff check . && uv run ruff format --check .

fmt:
	-$(SQLFLUFF) fix core plugins apps connectors/telegram/schema.sql
	cd clients/python && uv run ruff check --fix . && uv run ruff format .
	cd connectors/tui && uv run ruff check --fix . && uv run ruff format .
	cd connectors/telegram && uv run ruff check --fix . && uv run ruff format .

tui:
	cd connectors/tui && uv run pg-agent-tui

telegram:
	$(PSQL) -d agent -f connectors/telegram/schema.sql
	cd connectors/telegram && uv run pg-agent-telegram
