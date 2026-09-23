'use strict';
const http = require('http');
const path = require('path');
const { createStore } = require('./lib/store');
const { createApi } = require('./lib/api');

const PORT = Number(process.env.PORT) || 3000;
const DATA_FILE = process.env.DATA_FILE || path.join(process.env.DATA_DIR || path.join(__dirname, 'data'), 'db.json');

const store = createStore(DATA_FILE);
const api = createApi(store);

http.createServer(api.handle).listen(PORT, () => {
  console.log(`Poker Night running on http://localhost:${PORT} (data: ${DATA_FILE})`);
});
