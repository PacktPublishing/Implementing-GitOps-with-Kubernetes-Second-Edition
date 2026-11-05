// Runs in CI before the image is built: `npm test`. No network, no Redis.
'use strict';

process.env.WEATHER_PROVIDER = 'mock';
delete process.env.REDIS_URL;

const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const { start } = require('../server');
const { spawnSync } = require('node:child_process');
const path = require('node:path');

let server;
let base;

before(() => {
  server = start(0);
  base = `http://127.0.0.1:${server.address().port}`;
});

after(() => server.close());

test('liveness and readiness answer without a cache', async () => {
  assert.equal((await fetch(`${base}/healthz`)).status, 200);
  const ready = await fetch(`${base}/readyz`);
  assert.equal(ready.status, 200);
  assert.equal((await ready.json()).cache, 'down');
});

test('weather is served and the cache is bypassed when Redis is absent', async () => {
  const res = await fetch(`${base}/api/weather?city=Zurich`);
  assert.equal(res.status, 200);
  assert.equal(res.headers.get('x-cache'), 'BYPASS');
  const body = await res.json();
  assert.equal(body.location.name, 'Zurich');
});

test('input is validated', async () => {
  const res = await fetch(`${base}/api/weather?city=${encodeURIComponent('<script>')}`);
  assert.equal(res.status, 400);
});

test('RED metrics are exposed', async () => {
  const text = await (await fetch(`${base}/metrics`)).text();
  assert.match(text, /http_requests_total\{method="GET",route="\/api\/weather",code="200"\}/);
  assert.match(text, /weather_cache_requests_total\{result="bypass"\}/);
});

test('the Key Vault placeholder value counts as no key', () => {
  // A fresh process, because the provider is chosen once at start-up.
  const env = { ...process.env, WEATHER_API_KEY: 'REPLACE_ME' };
  delete env.WEATHER_PROVIDER;
  const r = spawnSync(process.execPath, ['-e', "console.log(require('./server').config.provider)"],
    { cwd: path.join(__dirname, '..'), env, encoding: 'utf8' });
  assert.equal(r.stdout.trim(), 'mock');
});
