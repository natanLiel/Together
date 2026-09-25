'use strict';
// Pure game math: balances, settlements, and long-term stats. No I/O here.

const round2 = (n) => Math.round((Number(n) + Number.EPSILON) * 100) / 100;

function playerLines(game) {
  const lines = new Map();
  for (const p of game.players) {
    lines.set(p.userId, { userId: p.userId, buyIn: 0, buyIns: 0, pending: 0, cashChips: null, cashOut: null, net: null });
  }
  for (const e of game.entries) {
    const line = lines.get(e.userId);
    if (!line) continue;
    if (e.status === 'approved') { line.buyIn = round2(line.buyIn + e.amount); line.buyIns++; }
    else if (e.status === 'pending') line.pending = round2(line.pending + e.amount);
  }
  for (const line of lines.values()) {
    const co = game.cashouts[line.userId];
    if (co && co.chips != null) {
      line.cashChips = co.chips;
      line.cashOut = round2(co.chips * game.chipValue);
      line.net = round2(line.cashOut - line.buyIn);
    }
  }
  return [...lines.values()];
}

function gameTotals(game) {
  const lines = playerLines(game);
  const pot = round2(lines.reduce((s, l) => s + l.buyIn, 0));
  const cashedOut = round2(lines.reduce((s, l) => s + (l.cashOut || 0), 0));
  const playing = lines.filter((l) => l.buyIn > 0);
  const missing = playing.filter((l) => l.cashOut == null).map((l) => l.userId);
  const pending = game.entries.filter((e) => e.status === 'pending').length;
  return {
    pot,
    potChips: round2(pot / game.chipValue),
    cashedOut,
    difference: round2(cashedOut - pot),
    missingCashouts: missing,
    pendingEntries: pending,
    balanced: missing.length === 0 && Math.abs(cashedOut - pot) < 0.005,
  };
}

// Fewest-transfers-ish greedy settlement: biggest loser pays biggest winner.
function settle(nets) {
  const creditors = [], debtors = [];
  for (const { userId, net } of nets) {
    if (net > 0.004) creditors.push({ userId, left: net });
    else if (net < -0.004) debtors.push({ userId, left: -net });
  }
  creditors.sort((a, b) => b.left - a.left);
  debtors.sort((a, b) => b.left - a.left);
  const transfers = [];
  let i = 0, j = 0;
  while (i < debtors.length && j < creditors.length) {
    const pay = round2(Math.min(debtors[i].left, creditors[j].left));
    if (pay > 0) transfers.push({ from: debtors[i].userId, to: creditors[j].userId, amount: pay, paid: false });
    debtors[i].left = round2(debtors[i].left - pay);
    creditors[j].left = round2(creditors[j].left - pay);
    if (debtors[i].left <= 0.004) i++;
    if (creditors[j].left <= 0.004) j++;
  }
  return transfers;
}

// Every finished night a player sat in, oldest first.
function resultsFor(userId, games) {
  const out = [];
  for (const g of games) {
    if (g.status !== 'ended') continue;
    const line = playerLines(g).find((l) => l.userId === userId);
    if (!line || line.buyIn <= 0) continue;
    out.push({
      gameId: g.id, name: g.name, date: g.date, endedAt: g.endedAt, currency: g.currency,
      buyIn: line.buyIn, cashOut: line.cashOut || 0, net: line.net != null ? line.net : -line.buyIn,
      players: playerLines(g).filter((l) => l.buyIn > 0).length,
    });
  }
  return out.sort((a, b) => (a.date === b.date ? a.endedAt - b.endedAt : a.date < b.date ? -1 : 1));
}

function summarize(results) {
  const games = results.length;
  const totalBuyIn = round2(results.reduce((s, r) => s + r.buyIn, 0));
  const net = round2(results.reduce((s, r) => s + r.net, 0));
  const wins = results.filter((r) => r.net > 0).length;
  let streak = 0;
  for (let i = results.length - 1; i >= 0; i--) {
    const sign = Math.sign(results[i].net);
    if (sign === 0) break;
    if (streak === 0) streak = sign;
    else if (Math.sign(streak) === sign) streak += sign;
    else break;
  }
  let running = 0, peak = 0, maxDrawdown = 0;
  const curve = results.map((r) => {
    running = round2(running + r.net);
    peak = Math.max(peak, running);
    maxDrawdown = Math.max(maxDrawdown, round2(peak - running));
    return running;
  });
  const nets = results.map((r) => r.net);
  return {
    games,
    totalBuyIn,
    net,
    wins,
    losses: results.filter((r) => r.net < 0).length,
    winRate: games ? wins / games : 0,
    avg: games ? round2(net / games) : 0,
    roi: totalBuyIn ? net / totalBuyIn : 0,
    best: games ? Math.max(...nets) : 0,
    worst: games ? Math.min(...nets) : 0,
    streak,
    maxDrawdown,
    curve,
  };
}

// Stats split by currency; nights in different currencies are never added together.
function statsFor(userId, games) {
  const byCurrency = {};
  for (const r of resultsFor(userId, games)) (byCurrency[r.currency] = byCurrency[r.currency] || []).push(r);
  const out = {};
  for (const [cur, results] of Object.entries(byCurrency)) out[cur] = { ...summarize(results), results };
  const primary = Object.keys(out).sort((a, b) => out[b].games - out[a].games)[0] || null;
  return { primary, byCurrency: out };
}

function badges(summary) {
  if (!summary || !summary.games) return [];
  const b = [];
  if (summary.games >= 10) b.push({ icon: '🎖️', label: 'מהקבועים', hint: '10 ערבים ומעלה' });
  if (summary.streak >= 3) b.push({ icon: '🔥', label: `בוער ×${summary.streak}`, hint: 'רצף ניצחונות' });
  if (summary.streak <= -3) b.push({ icon: '🧊', label: `קר ×${-summary.streak}`, hint: 'רצף הפסדים' });
  if (summary.games >= 5 && summary.winRate >= 0.6) b.push({ icon: '🦈', label: 'כריש', hint: 'ניצחון ב־60% מהערבים ומעלה' });
  if (summary.games >= 5 && summary.winRate <= 0.25) b.push({ icon: '🐟', label: 'ספונסר השולחן', hint: 'רוב הערבים בהפסד' });
  if (summary.roi >= 0.3 && summary.games >= 3) b.push({ icon: '📈', label: 'תשואה גבוהה', hint: 'תשואה של 30%+ על הכניסות' });
  return b;
}

module.exports = { round2, playerLines, gameTotals, settle, resultsFor, summarize, statsFor, badges };
