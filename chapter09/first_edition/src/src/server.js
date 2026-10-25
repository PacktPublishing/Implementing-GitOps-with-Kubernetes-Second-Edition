const express = require('express');
const path = require('path');
const app = express();
const port = 8080;

app.get('/', (_req, res) => res.sendFile(path.join(__dirname, 'index.html')));
app.get('/data.csv', (_req, res) => res.sendFile(path.join(__dirname, 'data.csv')));

app.listen(port, () => {
    console.log(`Server running at http://localhost:${port}`);
});
