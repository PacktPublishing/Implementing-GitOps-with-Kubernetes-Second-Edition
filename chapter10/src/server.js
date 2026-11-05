// weather-app v3 – the Chapter 8 sample, grown into a small production service.
//
// What changed since Chapter 8, and why:
//   * /api/weather calls a real upstream (weatherapi.com) instead of reading a CSV.
//   * Responses are cached in Redis, so the service has a stateful dependency to
//     scale, secure and recover (Chapter 10, H4 and H5).
//   * /metrics exposes the RED signals (rate, errors, duration) that the canary
//     analysis and the KEDA scaler query (Chapter 10, H3 and H4; Chapter 11).
//   * The cache is OPTIONAL: if Redis is down the service keeps answering from the
//     upstream and reports "BYPASS". Readiness never depends on the cache, so a
//     cache outage cannot take the whole service out of rotation.
//   * FAULT_ERROR_RATE lets you inject failures to watch a canary roll back.
'use strict';

const express = require('express');
const path = require('path');
const { createClient } = require('redis');
const prom = require('@prometheus-io/client');

function realKey() {
  const key = process.env.WEATHER_API_KEY || '';
  return key === 'REPLACE_ME' ? '' : key;
}

const config = {
  port: Number(process.env.PORT || 8080),
  environment: process.env.APP_ENVIRONMENT || 'local',
  cloud: process.env.CLOUD_PROVIDER || 'unknown',
  revision: process.env.APP_REVISION || 'dev',
  // "weatherapi" calls https://api.weatherapi.com; "mock" returns synthetic data
  // so that the local kind loop and the tests need no API key.
  // The Key Vault secrets are created with the value REPLACE_ME (iac/azure);
  // until a real key is set, that placeholder means "no key".
  provider: process.env.WEATHER_PROVIDER || (realKey() ? 'weatherapi' : 'mock'),
  apiKey: realKey(),
  apiUrl: process.env.WEATHER_API_URL || 'https://api.weatherapi.com/v1/current.json',
  redisUrl: process.env.REDIS_URL || '',
  cacheTtlSeconds: Number(process.env.CACHE_TTL_SECONDS || 300),
  upstreamTimeoutMs: Number(process.env.UPSTREAM_TIMEOUT_MS || 3000),
  faultErrorRate: Math.min(Math.max(Number(process.env.FAULT_ERROR_RATE || 0), 0), 1),
};

// ---------------------------------------------------------------------------
// Metrics
// ---------------------------------------------------------------------------
const registry = new prom.Registry();
prom.collectDefaultMetrics({ register: registry });

const httpRequests = new prom.Counter({
  name: 'http_requests_total',
  help: 'HTTP requests handled, by route and status code',
  labelNames: ['method', 'route', 'code'],
  registers: [registry],
});
const httpDuration = new prom.Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request latency',
  labelNames: ['method', 'route', 'code'],
  buckets: [0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5],
  registers: [registry],
});
const cacheRequests = new prom.Counter({
  name: 'weather_cache_requests_total',
  help: 'Cache lookups by result (hit, miss, bypass)',
  labelNames: ['result'],
  registers: [registry],
});
const upstreamErrors = new prom.Counter({
  name: 'weather_upstream_errors_total',
  help: 'Failed calls to the weather provider',
  registers: [registry],
});

// ---------------------------------------------------------------------------
// Redis (optional)
// ---------------------------------------------------------------------------
let redis = null;
if (config.redisUrl) {
  redis = createClient({
    url: config.redisUrl,
    socket: {
      connectTimeout: 2000,
      // Back off up to 5 s between reconnect attempts; never give up.
      reconnectStrategy: (retries) => Math.min(retries * 200, 5000),
    },
  });
  redis.on('error', (err) => console.warn(`redis: ${err.message}`));
  redis.connect().catch((err) => console.warn(`redis: initial connect failed: ${err.message}`));
}
const cacheAvailable = () => Boolean(redis && redis.isReady);

// ---------------------------------------------------------------------------
// Weather provider
// ---------------------------------------------------------------------------
const CITY_PATTERN = /^[\p{L} .'-]{1,64}$/u;

async function fetchWeather(city) {
  if (config.provider === 'mock') {
    // Deterministic per city, so repeated calls are comparable in tests.
    const seed = [...city].reduce((acc, ch) => acc + ch.charCodeAt(0), 0);
    return { location: { name: city }, current: { temp_c: (seed % 35) - 5, condition: { text: 'Mock' } } };
  }
  const url = new URL(config.apiUrl);
  url.searchParams.set('key', config.apiKey);
  url.searchParams.set('q', city);
  url.searchParams.set('aqi', 'no');
  const response = await fetch(url, { signal: AbortSignal.timeout(config.upstreamTimeoutMs) });
  if (!response.ok) {
    throw new Error(`provider returned ${response.status}`);
  }
  return response.json();
}

// ---------------------------------------------------------------------------
// HTTP
// ---------------------------------------------------------------------------
const app = express();
app.disable('x-powered-by');

// Record rate, errors and duration for every request except the scrape itself.
app.use((req, res, next) => {
  if (req.path === '/metrics') return next();
  const stop = httpDuration.startTimer();
  res.on('finish', () => {
    const labels = { method: req.method, route: req.route ? req.route.path : 'static', code: String(res.statusCode) };
    httpRequests.inc(labels);
    stop(labels);
  });
  next();
});

app.use(express.static(path.join(__dirname, 'public'), { index: 'index.html' }));

// Liveness: the process is up and the event loop is responsive.
app.get('/healthz', (_req, res) => res.status(200).json({ status: 'ok' }));

// Readiness: able to serve traffic. Deliberately independent of Redis.
app.get('/readyz', (_req, res) => res.status(200).json({ status: 'ready', cache: cacheAvailable() ? 'up' : 'down' }));

app.get('/api/info', (_req, res) =>
  res.json({ environment: config.environment, cloud: config.cloud, revision: config.revision, provider: config.provider })
);

app.get('/api/weather', async (req, res) => {
  if (config.faultErrorRate > 0 && Math.random() < config.faultErrorRate) {
    return res.status(500).json({ error: 'injected fault' });
  }
  const city = String(req.query.city || 'Zurich').trim();
  if (!CITY_PATTERN.test(city)) {
    return res.status(400).json({ error: 'invalid city' });
  }
  const key = `weather:${city.toLowerCase()}`;

  if (cacheAvailable()) {
    try {
      const cached = await redis.get(key);
      if (cached) {
        cacheRequests.inc({ result: 'hit' });
        res.set('X-Cache', 'HIT');
        return res.json(JSON.parse(cached));
      }
      cacheRequests.inc({ result: 'miss' });
      res.set('X-Cache', 'MISS');
    } catch (err) {
      console.warn(`redis get failed: ${err.message}`);
      cacheRequests.inc({ result: 'bypass' });
      res.set('X-Cache', 'BYPASS');
    }
  } else {
    cacheRequests.inc({ result: 'bypass' });
    res.set('X-Cache', 'BYPASS');
  }

  try {
    const data = await fetchWeather(city);
    if (cacheAvailable()) {
      redis.set(key, JSON.stringify(data), { EX: config.cacheTtlSeconds }).catch(() => {});
    }
    return res.json(data);
  } catch (err) {
    upstreamErrors.inc();
    console.warn(`provider call failed: ${err.message}`);
    return res.status(502).json({ error: 'weather provider unavailable' });
  }
});

app.get('/metrics', async (_req, res) => {
  res.set('Content-Type', registry.contentType);
  res.end(await registry.metrics());
});

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------
function start(port = config.port) {
  const server = app.listen(port, () => {
    console.log(
      `weather-app listening on :${server.address().port} ` +
        `(env=${config.environment}, provider=${config.provider}, cache=${config.redisUrl ? 'redis' : 'none'}, revision=${config.revision})`
    );
  });
  // Let Kubernetes terminate the pod cleanly instead of waiting for SIGKILL.
  for (const signal of ['SIGTERM', 'SIGINT']) {
    process.once(signal, () => {
      console.log(`${signal} received, draining connections`);
      server.close(async () => {
        if (redis) await redis.quit().catch(() => {});
        process.exit(0);
      });
    });
  }
  return server;
}

if (require.main === module) {
  start();
}

module.exports = { app, start, config };
