const express = require('express');
const fs = require('fs');
const path = require('path');
const app = express();
const port = 8080;
const indexPage = fs.readFileSync(path.join(__dirname, 'index.html'));
const data = fs.readFileSync(path.join(__dirname, 'data.csv'));

app.get('/', (_req, res) => res.type('html').send(indexPage));
app.get('/data.csv', (_req, res) => res.type('text/csv').send(data));

app.listen(port, () => {
    console.log(`Server running at http://localhost:${port}`);
});
