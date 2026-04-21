#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ -f .env ]]; then
  set -a; source .env; set +a
fi

if [[ -z "${EIA_API_KEY:-}" ]]; then
  echo "ERROR: EIA_API_KEY not set. Register a free key at https://www.eia.gov/opendata/register.php" >&2
  echo "       then add 'EIA_API_KEY=...' to .env" >&2
  exit 1
fi

BACKFILL=0
if [[ "${1:-}" == "--backfill" ]]; then
  BACKFILL=1
fi

mkdir -p data
DB="data/oil.duckdb"

if [[ -f "$DB" && "$BACKFILL" == "0" ]]; then
  RANGE="1mo"
  START_DATE="$(date -u -v-30d +%Y-%m-%d 2>/dev/null || date -u -d '30 days ago' +%Y-%m-%d)"
else
  RANGE="2y"
  START_DATE="$(date -u -v-2y +%Y-%m-%d 2>/dev/null || date -u -d '2 years ago' +%Y-%m-%d)"
fi
END_DATE="$(date -u +%Y-%m-%d)"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Fetching EIA RBRTE [$START_DATE → $END_DATE]..."
EIA_URL="https://api.eia.gov/v2/petroleum/pri/spt/data/?api_key=${EIA_API_KEY}&frequency=daily&data[0]=value&facets[series][]=RBRTE&start=${START_DATE}&end=${END_DATE}&sort[0][column]=period&sort[0][direction]=asc&offset=0&length=5000"
curl -gfsS --compressed "$EIA_URL" > "$TMP/eia.json"
EIA_TOTAL=$(jq -r '.response.total // "?"' "$TMP/eia.json")
jq -r '.response.data[] | select(.value != null) | [.period, .value] | @tsv' "$TMP/eia.json" > "$TMP/eia.tsv"
EIA_ROWS=$(wc -l < "$TMP/eia.tsv" | tr -d ' ')
echo "  $EIA_ROWS rows (server reports total=$EIA_TOTAL available)"
if [[ "$EIA_ROWS" == "0" ]]; then
  echo "ERROR: EIA returned no rows. Response head:" >&2
  head -c 400 "$TMP/eia.json" >&2; echo >&2
  exit 1
fi

echo "Fetching Yahoo BZ=F (range=$RANGE)..."
curl -fsS --compressed -A "Mozilla/5.0" "https://query1.finance.yahoo.com/v8/finance/chart/BZ=F?interval=1d&range=${RANGE}" \
  | jq -r '
      .chart.result[0] as $r
      | [range(0; ($r.timestamp | length))][]
      | . as $i
      | select($r.indicators.quote[0].close[$i] != null)
      | [($r.timestamp[$i] | strftime("%Y-%m-%d")), $r.indicators.quote[0].close[$i]]
      | @tsv' \
  > "$TMP/yahoo.tsv"
YAHOO_ROWS=$(wc -l < "$TMP/yahoo.tsv" | tr -d ' ')
echo "  $YAHOO_ROWS rows"
if [[ "$YAHOO_ROWS" == "0" ]]; then
  echo "ERROR: Yahoo BZ=F returned no rows." >&2
  exit 1
fi

echo "Upserting into $DB..."
duckdb "$DB" <<SQL
CREATE TABLE IF NOT EXISTS daily (
  date        DATE PRIMARY KEY,
  dated_brent DOUBLE,
  brent_1m    DOUBLE,
  spread      DOUBLE,
  tankers_out INTEGER,
  updated_at  TIMESTAMP
);

CREATE OR REPLACE TEMP TABLE eia_stage AS
  SELECT column0::DATE AS date, column1::DOUBLE AS value
  FROM read_csv('$TMP/eia.tsv', delim='\t', header=false, columns={'column0':'VARCHAR','column1':'VARCHAR'});

CREATE OR REPLACE TEMP TABLE yahoo_stage AS
  SELECT column0::DATE AS date, column1::DOUBLE AS close
  FROM read_csv('$TMP/yahoo.tsv', delim='\t', header=false, columns={'column0':'VARCHAR','column1':'VARCHAR'});

CREATE OR REPLACE TEMP TABLE tanker_stage AS
  SELECT Date::DATE AS date, Value_Blue::INTEGER AS tankers_out
  FROM read_csv_auto('transit_data.csv');

INSERT INTO daily (date, dated_brent, brent_1m, spread, tankers_out, updated_at)
SELECT
  COALESCE(d.date, y.date, t.date) AS date,
  d.value, y.close, d.value - y.close, t.tankers_out, now()
FROM eia_stage d
FULL OUTER JOIN yahoo_stage y USING (date)
FULL OUTER JOIN tanker_stage t USING (date)
ON CONFLICT (date) DO UPDATE SET
  dated_brent = COALESCE(excluded.dated_brent, daily.dated_brent),
  brent_1m    = COALESCE(excluded.brent_1m,    daily.brent_1m),
  spread      = COALESCE(excluded.dated_brent, daily.dated_brent)
              - COALESCE(excluded.brent_1m,    daily.brent_1m),
  tankers_out = COALESCE(excluded.tankers_out, daily.tankers_out),
  updated_at  = excluded.updated_at;

.print --- summary ---
SELECT
  count(*)                                           AS rows,
  count(*) FILTER (WHERE dated_brent IS NOT NULL)    AS dated_brent_rows,
  count(*) FILTER (WHERE brent_1m    IS NOT NULL)    AS brent_1m_rows,
  count(*) FILTER (WHERE tankers_out IS NOT NULL)    AS tanker_rows,
  max(date)                                          AS latest_date,
  round(max(spread) FILTER (WHERE date = (SELECT max(date) FROM daily WHERE spread IS NOT NULL)), 3) AS latest_spread,
  max(tankers_out) FILTER (WHERE date = (SELECT max(date) FROM daily WHERE tankers_out IS NOT NULL)) AS latest_tankers
FROM daily;
SQL
