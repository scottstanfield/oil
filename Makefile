.PHONY: help install update backfill serve db clean

DB := data/oil.duckdb
PORT ?= 3000

help:
	@awk 'BEGIN {FS=":.*##"; printf "\nTargets:\n"} /^[a-zA-Z_-]+:.*##/ {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

install: ## bun install dependencies
	bun install

update: ## incremental refresh (last 30 days)
	bash bin/update.sh

backfill: ## force 2-year refetch of EIA + Yahoo
	bash bin/update.sh --backfill

serve: ## start the Node server (PORT=3000 by default)
	PORT=$(PORT) bun run server.mjs

db: ## open a DuckDB shell against the local DB
	duckdb $(DB)

clean: ## remove the local DuckDB file
	rm -f $(DB)
