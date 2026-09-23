'use strict';
// Tiny JSON-file database. The whole dataset lives in memory and is written
// atomically (temp file + rename) after every change. Plenty for a friend group.
const fs = require('fs');
const path = require('path');

function createStore(file) {
  let data = { users: {}, sessions: {}, games: {} };
  if (file && fs.existsSync(file)) {
    data = { ...data, ...JSON.parse(fs.readFileSync(file, 'utf8')) };
  }
  function save() {
    if (!file) return;
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const tmp = file + '.tmp';
    fs.writeFileSync(tmp, JSON.stringify(data));
    fs.renameSync(tmp, file);
  }
  return { data, save };
}

module.exports = { createStore };
