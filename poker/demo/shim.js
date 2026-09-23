// Browser stand-in for the server: runs lib/api.js in the page and answers
// the app's /api/ calls from it. Data lives in this browser only.
(function () {
  'use strict';
  const HEX = '0123456789abcdef';
  class Buf extends Uint8Array {
    toString(enc) {
      if (enc === 'hex') return Array.from(this, (b) => HEX[b >> 4] + HEX[b & 15]).join('');
      let bin = '';
      for (const b of this) bin += String.fromCharCode(b);
      return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
    }
  }
  const builtins = {
    crypto: {
      randomBytes(n) { const b = new Buf(n); crypto.getRandomValues(b); return b; },
      // Not scrypt: the demo only ever checks PINs against itself, on this phone.
      scryptSync(pin, salt, len) {
        const s = String(salt) + ':' + String(pin);
        const out = new Buf(len);
        let h1 = 0xdeadbeef, h2 = 0x41c6ce57;
        for (let round = 0; round < len; round++) {
          for (let i = 0; i < s.length; i++) {
            const c = s.charCodeAt(i) + round;
            h1 = Math.imul(h1 ^ c, 2654435761); h2 = Math.imul(h2 ^ c, 1597334677);
          }
          h1 = Math.imul(h1 ^ (h1 >>> 16), 2246822507) ^ Math.imul(h2 ^ (h2 >>> 13), 3266489909);
          out[round] = h1 & 255;
        }
        return out;
      },
    },
    fs: {},
    path: { join: () => '', extname: () => '', normalize: (p) => p },
  };
  const defs = {}, cache = {};
  const req = (name) => {
    if (builtins[name]) return builtins[name];
    if (!cache[name]) { const m = { exports: {} }; cache[name] = m; defs[name](m, m.exports, req, ''); }
    return cache[name].exports;
  };
  window.PN_DEFINE = (name, fn) => { defs[name] = fn; };
  window.PN_BOOT_DEMO = function () {
    const { createApi } = req('./api');
    const KEY = 'pn.demo.db';
    let data = null;
    try { data = JSON.parse(localStorage.getItem(KEY)); } catch { /* storage blocked */ }
    const fresh = !data;
    data = data || { users: {}, sessions: {}, games: {} };
    const store = { data, save() { try { localStorage.setItem(KEY, JSON.stringify(data)); } catch { /* storage blocked */ } } };
    const api = createApi(store);
    const call = (method, url, body, token) => api.dispatch(method, url, { authorization: token ? 'Bearer ' + token : '' }, body).body;

    const realFetch = window.fetch.bind(window);
    window.fetch = async (url, opts = {}) => {
      if (typeof url !== 'string' || !url.startsWith('/api/')) return realFetch(url, opts);
      const h = opts.headers || {};
      const out = api.dispatch(opts.method || 'GET', url, { authorization: h.Authorization || '' }, opts.body ? JSON.parse(opts.body) : {});
      return new Response(JSON.stringify(out.body), { status: out.status, headers: { 'Content-Type': 'application/json' } });
    };

    function newSession(userId) {
      const token = 'demo-' + Math.random().toString(36).slice(2) + Date.now().toString(36);
      data.sessions[token] = { userId, createdAt: Date.now() };
      store.save();
      const u = data.users[userId];
      return { token, user: { id: u.id, name: u.name, color: u.color } };
    }

    if (fresh) {
      const P = {};
      for (const n of ['Natan', 'Dana', 'Avi', 'Yoni', 'Shira']) P[n] = call('POST', '/api/signup', { name: n, pin: '1234' });
      const day = (weeksAgo) => {
        const d = new Date(Date.now() - weeksAgo * 7 * 864e5);
        return new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 10);
      };
      // [weeks ago, { player: [[buy-ins], final chips] }] at 1 chip = ₪5. Chips always add up to the pot.
      const nights = [
        [4, { Natan: [[100], 30], Dana: [[100, 100], 50], Avi: [[100], 0], Yoni: [[100], 40], Shira: [[100], 0] }],
        [3, { Natan: [[100, 50], 40], Dana: [[100], 10], Avi: [[100], 40], Yoni: [[100], 0] }],
        [2, { Natan: [[100], 15], Dana: [[100], 25], Avi: [[100, 100], 30], Yoni: [[100], 40], Shira: [[100], 10] }],
        [1, { Natan: [[200], 20], Dana: [[100], 0], Avi: [[100], 40], Shira: [[100], 40] }],
      ];
      for (const [ago, seats] of nights) {
        const g = call('POST', '/api/games', { name: 'Poker night', date: day(ago), location: "Natan's place", currency: 'ILS', chipValue: 5, buyIns: [50, 100, 200] }, P.Natan.token);
        for (const [n, [buys, chips]] of Object.entries(seats)) {
          if (n !== 'Natan') call('POST', `/api/invite/${g.code}/join`, {}, P[n].token);
          for (const a of buys) call('POST', `/api/games/${g.id}/entries`, { amount: a, userId: P[n].user.id }, P.Natan.token);
          call('PUT', `/api/games/${g.id}/cashouts/${P[n].user.id}`, { chips }, P.Natan.token);
        }
        const ended = call('POST', `/api/games/${g.id}/end`, {}, P.Natan.token);
        ended.settlements.forEach((t, i) => call('POST', `/api/games/${g.id}/settlements/${i}`, { paid: true }, P.Natan.token));
      }
      const g = call('POST', '/api/games', { name: 'Tonight', location: "Natan's place", currency: 'ILS', chipValue: 5, buyIns: [50, 100, 200] }, P.Natan.token);
      for (const n of ['Dana', 'Avi', 'Yoni']) call('POST', `/api/invite/${g.code}/join`, {}, P[n].token);
      call('POST', `/api/games/${g.id}/entries`, { amount: 100 }, P.Natan.token);
      for (const n of ['Dana', 'Avi']) {
        const x = call('POST', `/api/games/${g.id}/entries`, { amount: 100 }, P[n].token);
        call('POST', `/api/games/${g.id}/entries/${x.entries[x.entries.length - 1].id}/approve`, {}, P.Natan.token);
      }
      call('POST', `/api/games/${g.id}/entries`, { amount: 100 }, P.Avi.token);
      call('POST', `/api/games/${g.id}/entries`, { amount: 50 }, P.Yoni.token);
      window.PN_DEMO_SESSION = P.Natan;
      try {
        for (const k of Object.keys(localStorage)) if (k.startsWith('pn.') && k !== KEY) localStorage.removeItem(k);
        localStorage.setItem('pn.token', JSON.stringify(P.Natan.token));
        localStorage.setItem('pn.user', JSON.stringify(P.Natan.user));
      } catch { /* storage blocked */ }
    } else {
      const first = Object.values(data.users)[0];
      window.PN_DEMO_SESSION = first ? newSession(first.id) : { token: null, user: null };
    }
    window.PN_DEMO = { data, newSession, KEY };
  };
})();
