FROM postgres:17-bookworm

# http + ca-certificates: model and tool calls over HTTPS; plpgsql_check: static analysis; pgtap + pg_prove: tests.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        postgresql-17-http=1.7.2-2.pgdg12+2 \
        postgresql-17-plpgsql-check=2.10.13-1.pgdg12+1 \
        postgresql-17-pgtap=1.3.4-1.pgdg12+1 \
        libtap-parser-sourcehandler-pgtap-perl=3.37-1.pgdg120+1 \
    && rm -rf /var/lib/apt/lists/*
