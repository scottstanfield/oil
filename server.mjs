import { DuckDBInstance } from '@duckdb/node-api';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DB_PATH = join(__dirname, 'data', 'oil.duckdb');
const PUBLIC_DIR = join(__dirname, 'public');
const PORT = process.env.PORT ?? 3000;

const instance = await DuckDBInstance.create(DB_PATH, { access_mode: 'READ_ONLY' });
const conn = await instance.connect();

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js':   'application/javascript; charset=utf-8',
  '.css':  'text/css; charset=utf-8',
};

const VENDOR = {
  '/uplot.iife.min.js': 'node_modules/uplot/dist/uPlot.iife.min.js',
  '/uplot.css':         'node_modules/uplot/dist/uPlot.min.css',
};

createServer(async (req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);
  try {
    if (url.pathname === '/api/series') {
      const from = url.searchParams.get('from');
      const to   = url.searchParams.get('to');
      const where = [];
      const params = [];
      if (from) { where.push(`date >= $${params.length + 1}::DATE`); params.push(from); }
      if (to)   { where.push(`date <= $${params.length + 1}::DATE`); params.push(to); }
      const sql = `
        SELECT strftime(date, '%Y-%m-%d') AS date, dated_brent, brent_1m, spread, tankers_out
        FROM daily
        ${where.length ? 'WHERE ' + where.join(' AND ') : ''}
        ORDER BY date
      `;
      const reader = await conn.runAndReadAll(sql, params);
      const cols = reader.getColumnsObjectJS();
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify(cols));
      return;
    }

    const vendorPath = VENDOR[url.pathname];
    if (vendorPath) {
      const data = await readFile(join(__dirname, vendorPath));
      res.writeHead(200, { 'content-type': MIME[extname(vendorPath)] });
      res.end(data);
      return;
    }

    const path = url.pathname === '/' ? '/index.html' : url.pathname;
    const data = await readFile(join(PUBLIC_DIR, path));
    res.writeHead(200, { 'content-type': MIME[extname(path)] ?? 'application/octet-stream' });
    res.end(data);
  } catch (e) {
    res.writeHead(e.code === 'ENOENT' ? 404 : 500);
    res.end(String(e.message ?? e));
  }
}).listen(PORT, () => console.log(`http://localhost:${PORT}`));
