# oil

Daily time-series tracker for Strait of Hormuz tanker traffic and the Brent **Dated-to-Frontline spread** — physical Brent (Dated) minus front-month future (1st Line). A widening positive spread is the classic supply-shock signature: physical barrels bid up relative to paper.

Stack: a single DuckDB file, a bash updater, and a small Bun-installed Node server with two synced [uPlot](https://github.com/leeoniya/uPlot) charts.

Transit data taken from a screenshot from this video:
https://youtu.be/wWSnAmL3C7Y?si=29-TmVaejtVzpC0M&t=775

And sent to Google Gemini Pro 1.5 for processing by hand.
`This is close to a daily tracker of ship data transiting straight of hormuz. The x axis is the date, using a mix of formats (DD/MM/YYYY) and DD-MMM-YY. And the X axis labels are diagonal. The stacked bar chart has two dimensions: eastbound and westbound traffic. I want a CSV file with one row per day, with two columns, one for eastbound and other for westbound. The Maximum looks like 135 when both are combined. Minimum is near 0. I don't care about the 3 lines of text at the bottom.`



## Setup

1. Register a free EIA API key (instant): https://www.eia.gov/opendata/register.php
2. Drop it into `.env`:
   ```
   EIA_API_KEY=your_key_here
   ```
3. Install + backfill + serve:
   ```
   make install
   make backfill
   make serve
   ```

Open http://localhost:3000.

## Layout

```
bin/update.sh      # idempotent updater (EIA + Yahoo + transit_data.csv -> DuckDB upsert)
server.mjs         # Bun-run Node HTTP server, /api/series + static
public/            # index.html + app.js (two stacked uPlot charts)
transit_data.csv   # tanker counts (date, eastbound, westbound; total = eastbound + westbound)
data/oil.duckdb    # created on first update; gitignored
```

## Data sources

| Series | Source | Notes |
| --- | --- | --- |
| Dated Brent (spot) | EIA `RBRTE` daily, via `petroleum/pri/spt/data` | Free key. Close proxy for Platts Dated Brent assessment, not identical. |
| Brent 1st Line (future) | Yahoo Finance `BZ=F`, daily close | Free, no key. ICE Brent front-month continuous. |
| Hormuz transits | Local `transit_data.csv`, `eastbound + westbound` | Static snapshot for now (2026-02-01 → 2026-04-07). |

## Updater behaviour

- First run (no DB): backfills 2 years of EIA + Yahoo, ingests the full tanker CSV.
- Subsequent runs: refreshes the last 30 days (cheap overlap so re-runs self-heal).
- `bin/update.sh --backfill` (or `make backfill`): force the 2-year window again.

The summary line prints `dated_brent_rows` / `brent_1m_rows` / `tanker_rows` so a partial pull is loud.

## Schema

```sql
CREATE TABLE daily (
  date        DATE PRIMARY KEY,
  dated_brent DOUBLE,    -- USD/bbl, EIA RBRTE
  brent_1m    DOUBLE,    -- USD/bbl, Yahoo BZ=F close
  spread      DOUBLE,    -- dated_brent - brent_1m
  tankers_out INTEGER,   -- transit_data.csv eastbound + westbound; NULL outside CSV range
  updated_at  TIMESTAMP
);
```

## Make targets

Run `make` for the list. Common ones:

- `make install` — `bun install`
- `make update` — incremental (last 30 days)
- `make backfill` — force 2-year refetch
- `make serve` — start the Node server on port 3000
- `make db` — open a DuckDB shell against `data/oil.duckdb`
- `make clean` — remove `data/oil.duckdb`
