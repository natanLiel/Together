'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { settle, summarize } = require('../lib/logic');

test('settle: debts cover winnings with few transfers', () => {
  const t = settle([{ userId: 'a', net: 150 }, { userId: 'b', net: 50 }, { userId: 'c', net: -120 }, { userId: 'd', net: -80 }]);
  const recv = {}, paid = {};
  for (const x of t) { recv[x.to] = (recv[x.to] || 0) + x.amount; paid[x.from] = (paid[x.from] || 0) + x.amount; }
  assert.deepEqual(recv, { a: 150, b: 50 });
  assert.deepEqual(paid, { c: 120, d: 80 });
  assert.ok(t.length <= 3);
});

test('summarize: streaks, win rate, drawdown', () => {
  const s = summarize([{ net: 100, buyIn: 100 }, { net: -50, buyIn: 100 }, { net: 30, buyIn: 100 }, { net: 20, buyIn: 100 }]);
  assert.equal(s.games, 4);
  assert.equal(s.net, 100);
  assert.equal(s.winRate, 0.75);
  assert.equal(s.streak, 2);
  assert.equal(s.maxDrawdown, 50);
  assert.equal(s.best, 100);
  assert.equal(s.worst, -50);
});
