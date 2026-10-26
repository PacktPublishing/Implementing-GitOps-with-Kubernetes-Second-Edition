const express = require('express');
const fs = require('fs');
const path = require('path');

const app = express();
const port = process.env.PORT || 8080;

// Surfaced in the UI so that a reader can tell which cloud served the request.
const cloud = process.env.CLOUD_PROVIDER || 'unknown';
const revision = process.env.APP_REVISION || 'dev';

app.use(express.static(path.join(__dirname, 'public'), { index: 'index.html' }));

let dataAvailable = false;
fs.access(path.join(__dirname, 'public', 'data.csv'), fs.constants.R_OK, (err) => {
  dataAvailable = !err;
});

// Liveness: the process is up.
app.get('/healthz', (_req, res) => res.status(200).json({ status: 'ok' }));

// Readiness: the process is able to serve the data file.
app.get('/readyz', (_req, res) =>
  dataAvailable ? res.status(200).json({ status: 'ready' }) : res.status(503).json({ status: 'unavailable' })
);

app.get('/api/info', (_req, res) => res.json({ cloud, revision }));

const server = app.listen(port, () => {
  console.log(`weather-app listening on :${port} (cloud=${cloud}, revision=${revision})`);
});

// Let Kubernetes terminate the pod cleanly instead of waiting for SIGKILL.
for (const signal of ['SIGTERM', 'SIGINT']) {
  process.on(signal, () => {
    console.log(`${signal} received, draining connections`);
    server.close(() => process.exit(0));
  });
}
