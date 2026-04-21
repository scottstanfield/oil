const RANGES = { '30d': 30, '90d': 90, '1y': 365, 'all': null };
const SYNC_KEY = 'oil';

let priceChart = null;
let tankerChart = null;

function rangeQS(range) {
  const days = RANGES[range];
  if (!days) return '';
  const to = new Date();
  const from = new Date(to.getTime() - days * 86400_000);
  return `?from=${from.toISOString().slice(0, 10)}&to=${to.toISOString().slice(0, 10)}`;
}

async function load(range) {
  const res = await fetch(`/api/series${rangeQS(range)}`);
  const data = await res.json();
  const xs = data.date.map(d => new Date(d + 'T00:00:00Z').getTime() / 1000);
  render(xs, data);
}

function destroy() {
  if (priceChart)  { priceChart.destroy();  priceChart  = null; }
  if (tankerChart) { tankerChart.destroy(); tankerChart = null; }
}

function render(xs, data) {
  destroy();

  const cursor = { sync: { key: SYNC_KEY, setSeries: false } };
  const priceWidth  = document.getElementById('prices').clientWidth;
  const tankerWidth = document.getElementById('tankers').clientWidth;

  priceChart = new uPlot({
    title: 'Brent prices (USD/bbl) and Dated-to-Frontline spread',
    width: priceWidth,
    height: 320,
    cursor,
    scales: { usd: {}, spread: {} },
    series: [
      {},
      { label: 'Dated Brent',    stroke: '#1f77b4', width: 1.5, scale: 'usd' },
      { label: 'Brent 1st Line', stroke: '#ff7f0e', width: 1.5, scale: 'usd' },
      { label: 'Spread',         stroke: '#2ca02c', width: 2,   scale: 'spread' },
    ],
    axes: [
      {},
      { scale: 'usd',    label: 'USD/bbl' },
      { scale: 'spread', side: 1, label: 'Spread (USD)' },
    ],
  }, [xs, data.dated_brent, data.brent_1m, data.spread], document.getElementById('prices'));

  tankerChart = new uPlot({
    title: 'Strait of Hormuz — daily tanker transits (eastbound + westbound)',
    width: tankerWidth,
    height: 220,
    cursor,
    series: [
      {},
      { label: 'Tankers out', stroke: '#d62728', fill: 'rgba(214,39,40,0.15)', width: 1.5 },
    ],
    axes: [{}, { label: 'Tankers' }],
  }, [xs, data.tankers_out], document.getElementById('tankers'));
}

function activeRange() {
  return document.querySelector('button.active').dataset.range;
}

document.querySelectorAll('button[data-range]').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('button[data-range]').forEach(b => b.classList.remove('active'));
    btn.classList.add('active');
    load(btn.dataset.range);
  });
});

let resizeTimer;
window.addEventListener('resize', () => {
  clearTimeout(resizeTimer);
  resizeTimer = setTimeout(() => load(activeRange()), 150);
});

load('90d');
