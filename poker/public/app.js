/* Poker Night — single-page app. No framework; views are template strings. */
'use strict';

const $app = document.getElementById('app');
const $tabs = document.getElementById('tabs');
const $dialog = document.getElementById('dialog');
const PH = window.PokerHand;

const CURRENCY = {
  ILS: { symbol: '₪', label: 'NIS' },
  USD: { symbol: '$', label: 'USD' },
  EUR: { symbol: '€', label: 'EUR' },
  GBP: { symbol: '£', label: 'GBP' },
};
const MULTIPLIERS = [1, 2, 3, 4, 5];

const store = {
  get(k, d) { try { const v = localStorage.getItem(k); return v == null ? d : JSON.parse(v); } catch { return d; } },
  set(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch { /* private mode */ } },
  del(k) { try { localStorage.removeItem(k); } catch { /* private mode */ } },
};

const state = {
  token: store.get('pn.token', null) || (window.PN_DEMO_SESSION || {}).token || null,
  user: store.get('pn.user', null) || (window.PN_DEMO_SESSION || {}).user || null,
  me: null,
  game: null,
  openPlayer: null,
  poll: null,
};

// ---------------------------------------------------------------- helpers
const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const nf = new Intl.NumberFormat('en-US', { maximumFractionDigits: 2 });
const sym = (cur) => (CURRENCY[cur] || { symbol: '' }).symbol;
const money = (n, cur) => `${n < 0 ? '−' : ''}${sym(cur)}${nf.format(Math.abs(n))}`;
const signed = (n, cur) => (n > 0 ? '+' : '') + money(n, cur);
const chips = (n) => nf.format(n);
const pct = (x) => `${Math.round(x * 100)}%`;
const netClass = (n) => (n > 0 ? 'win' : n < 0 ? 'lose' : '');
const initials = (name) => String(name || '?').split(' ').map((w) => w[0]).join('').slice(0, 2).toUpperCase();
const avatar = (u, cls = '') => `<span class="avatar ${cls}" style="background:${esc(u && u.color || '#555')}">${esc(initials(u && u.name))}</span>`;
const fmtDate = (d) => new Date(d + 'T12:00:00').toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' });
const ago = (t) => {
  const s = Math.round((Date.now() - t) / 1000);
  if (s < 60) return 'just now';
  if (s < 3600) return `${Math.floor(s / 60)}m ago`;
  if (s < 86400) return `${Math.floor(s / 3600)}h ago`;
  return new Date(t).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
};
const todayISO = () => {
  const d = new Date();
  return new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 10);
};

function toast(msg, err) {
  const t = document.getElementById('toast');
  t.textContent = msg;
  t.className = 'show' + (err ? ' err' : '');
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => { t.className = ''; }, err ? 3800 : 2200);
}

async function api(method, url, body) {
  const res = await fetch(url, {
    method,
    headers: { 'Content-Type': 'application/json', ...(state.token ? { Authorization: 'Bearer ' + state.token } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await res.json().catch(() => ({}));
  if (res.status === 401 && state.token) signOut(false);
  if (!res.ok) { const e = new Error(data.error || 'Something went wrong'); e.status = res.status; e.data = data; throw e; }
  return data;
}

async function copyText(text) {
  try { await navigator.clipboard.writeText(text); }
  catch {
    const ta = document.createElement('textarea');
    ta.value = text; document.body.appendChild(ta); ta.select();
    document.execCommand('copy'); ta.remove();
  }
  toast('Copied');
}
const whatsappUrl = (text) => 'https://wa.me/?text=' + encodeURIComponent(text);

function confirmDialog(title, body, okLabel = 'OK', danger = false) {
  return new Promise((resolve) => {
    $dialog.innerHTML = `<h2>${esc(title)}</h2><p class="muted">${esc(body)}</p>
      <div class="row" style="justify-content:flex-end;margin-top:14px">
        <button data-r="0" class="ghost">Cancel</button>
        <button data-r="1" class="${danger ? 'danger' : 'primary'}">${esc(okLabel)}</button></div>`;
    $dialog.onclick = (e) => {
      const b = e.target.closest('[data-r]');
      if (b) { $dialog.close(); resolve(b.dataset.r === '1'); }
    };
    $dialog.oncancel = () => resolve(false);
    $dialog.showModal();
  });
}

function promptDialog(title, { label = '', value = '', type = 'text', okLabel = 'Save', hint = '' } = {}) {
  return new Promise((resolve) => {
    $dialog.innerHTML = `<form method="dialog"><h2>${esc(title)}</h2>
      <div class="field"><label>${esc(label)}</label>
      <input name="v" type="${type}" inputmode="${type === 'number' ? 'decimal' : 'text'}" step="any" value="${esc(value)}" autofocus></div>
      ${hint ? `<p class="small muted">${esc(hint)}</p>` : ''}
      <div class="row" style="justify-content:flex-end">
        <button value="cancel" class="ghost">Cancel</button><button value="ok" class="primary">${esc(okLabel)}</button></div></form>`;
    $dialog.onclick = null;
    $dialog.onclose = () => {
      $dialog.onclose = null;
      resolve($dialog.returnValue === 'ok' ? $dialog.querySelector('input').value : null);
    };
    $dialog.returnValue = '';
    $dialog.showModal();
  });
}

function signOut(callServer = true) {
  if (callServer && state.token) api('POST', '/api/logout').catch(() => {});
  state.token = null; state.user = null; state.me = null;
  store.del('pn.token'); store.del('pn.user');
  location.hash = '#/login';
}

// ---------------------------------------------------------------- router
const routes = [
  [/^#\/login$/, viewLogin, { open: true }],
  [/^#\/join\/([A-Za-z0-9]+)$/, viewJoin, { open: true }],
  [/^#\/new$/, viewNewGame],
  [/^#\/game\/([\w-]+)$/, viewGame],
  [/^#\/stats$/, viewStats, { tab: 'stats' }],
  [/^#\/player\/([\w-]+)$/, viewPlayer, { tab: 'stats' }],
  [/^#\/hands$/, viewHands, { tab: 'hands', open: true }],
  [/^#\/timer$/, viewTimer, { tab: 'timer', open: true }],
  [/^#\/account$/, viewAccount],
  [/^#?\/?$/, viewHome, { tab: 'home' }],
];

async function router() {
  clearInterval(state.poll); state.poll = null;
  const hash = location.hash || '#/';
  let found = routes.find(([re]) => re.test(hash));
  if (!found) { location.hash = '#/'; return; }
  const [re, view, opts = {}] = found;
  if (!opts.open && !state.token) {
    if (hash !== '#/') store.set('pn.after', hash);
    location.hash = '#/login';
    return;
  }
  $tabs.hidden = !state.token && !['hands', 'timer'].includes(opts.tab);
  for (const a of $tabs.querySelectorAll('a')) a.classList.toggle('on', a.dataset.tab === opts.tab);
  const args = hash.match(re).slice(1);
  try { await view(...args); }
  catch (e) { $app.innerHTML = `<div class="card"><h2>Hmm.</h2><p>${esc(e.message)}</p><a class="btn" href="#/">Home</a></div>`; }
  window.scrollTo(0, 0);
}
window.addEventListener('hashchange', router);

// ---------------------------------------------------------------- login
async function viewLogin(inviteCode) {
  if (state.token) { location.hash = '#/'; return; }
  let invite = null;
  const code = inviteCode || store.get('pn.invite', null);
  if (code) invite = await api('GET', `/api/invite/${code}`).catch(() => null);
  const saved = store.get('pn.lastName', '');
  $app.innerHTML = `
    <div class="center" style="margin:28px 0 20px">
      <div class="logo">♠️♥️♣️♦️</div>
      <h1>Poker Night</h1>
      <p class="muted">Buy-ins, standings and bragging rights for your home game.</p>
    </div>
    ${invite ? `<div class="card gold"><h3>You're invited</h3>
      <h2>${esc(invite.name)}</h2>
      <p class="muted">${esc(fmtDate(invite.date))} · hosted by ${esc(invite.host)}${invite.location ? ' · ' + esc(invite.location) : ''}</p>
      <p class="small">Log in or pick a name + PIN to take a seat.</p></div>` : ''}
    <form class="card" id="auth">
      <div class="seg" style="margin-bottom:14px">
        <button type="button" data-mode="login" class="on">I have an account</button>
        <button type="button" data-mode="signup">I'm new</button>
      </div>
      <div class="field"><label for="name">Your name</label>
        <input id="name" name="name" autocomplete="username" value="${esc(saved)}" placeholder="e.g. Dan K" required maxlength="24"></div>
      <div class="field"><label for="pin">PIN (4–6 digits)</label>
        <input id="pin" name="pin" class="pin" type="password" inputmode="numeric" pattern="[0-9]*" autocomplete="current-password" minlength="4" maxlength="6" required></div>
      <button class="primary block" id="authBtn">Log in</button>
      <p class="small muted center" style="margin-top:10px" id="authHint">Friends see your name on the table, so use the one they know you by.</p>
    </form>
    <div class="row" style="justify-content:center;gap:18px">
      <a href="#/hands">🃏 Hand checker</a><a href="#/timer">⏱️ Blinds timer</a>
    </div>`;
  let mode = 'login';
  const form = document.getElementById('auth');
  form.querySelectorAll('[data-mode]').forEach((b) => b.addEventListener('click', () => {
    mode = b.dataset.mode;
    form.querySelectorAll('[data-mode]').forEach((x) => x.classList.toggle('on', x === b));
    document.getElementById('authBtn').textContent = mode === 'login' ? 'Log in' : 'Create account';
    document.getElementById('pin').autocomplete = mode === 'login' ? 'current-password' : 'new-password';
  }));
  if (!saved) form.querySelector('[data-mode="signup"]').click();
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    const name = form.name.value, pin = form.pin.value;
    try {
      const r = await api('POST', mode === 'login' ? '/api/login' : '/api/signup', { name, pin });
      state.token = r.token; state.user = r.user;
      store.set('pn.token', r.token); store.set('pn.user', r.user); store.set('pn.lastName', r.user.name);
      if (code) { store.del('pn.invite'); await joinAndGo(code); return; }
      const after = store.get('pn.after', null); store.del('pn.after');
      location.hash = after || '#/';
    } catch (err) { toast(err.message, true); }
  });
}

async function joinAndGo(code) {
  const r = await api('POST', `/api/invite/${code}/join`);
  location.hash = `#/game/${r.id}`;
}

async function viewJoin(code) {
  if (!state.token) { store.set('pn.invite', code); return viewLogin(code); }
  try { await joinAndGo(code); }
  catch (e) { $app.innerHTML = `<div class="card"><h2>Can't join</h2><p>${esc(e.message)}</p><a class="btn" href="#/">Home</a></div>`; }
}

// ---------------------------------------------------------------- home
async function viewHome() {
  const me = state.me = await api('GET', '/api/me');
  state.user = me.user; store.set('pn.user', me.user);
  const live = me.games.filter((g) => g.status === 'live');
  const past = me.games.filter((g) => g.status !== 'live');
  const prim = me.stats.primary && me.stats.byCurrency[me.stats.primary];
  const cur = me.stats.primary;
  $app.innerHTML = `
    <div class="hero-head">
      <a href="#/account">${avatar(me.user, 'lg')}</a>
      <div class="grow"><p class="muted small" style="margin:0">Welcome back</p><h1 style="margin:0">${esc(me.user.name)}</h1></div>
      <a href="#/account" class="btn icon-btn" aria-label="Account">⚙️</a>
    </div>
    ${prim ? `<a class="card" href="#/player/${me.user.id}" style="display:block;color:inherit;text-decoration:none">
      <div class="row between"><h3>Your record</h3><span class="small muted">All time · ${esc(CURRENCY[cur].label)} ›</span></div>
      <div class="tiles">
        <div class="tile"><div class="v ${netClass(prim.net)}">${signed(prim.net, cur)}</div><div class="k">Profit</div></div>
        <div class="tile"><div class="v">${prim.games}</div><div class="k">Nights</div></div>
        <div class="tile"><div class="v">${pct(prim.winRate)}</div><div class="k">Winning nights</div></div>
      </div>
      ${me.badges.length ? `<div class="row wrap" style="margin-top:10px">${me.badges.map((b) => `<span class="tag" title="${esc(b.hint)}">${b.icon} ${esc(b.label)}</span>`).join('')}</div>` : ''}
    </a>` : ''}
    <a class="btn primary block" href="#/new" style="min-height:56px;font-size:18px;margin-bottom:14px">＋ Open a new table</a>
    ${live.length ? `<div class="card"><h3>Live tables</h3><ul class="list">${live.map(gameItem).join('')}</ul></div>` : ''}
    <form class="card" id="joinForm">
      <h3>Got an invite code?</h3>
      <div class="row"><input name="code" placeholder="e.g. K7Q2XM" autocapitalize="characters" maxlength="12" class="grow">
      <button class="sm">Join</button></div>
    </form>
    <div class="card"><h3>Past nights</h3>
      ${past.length ? `<ul class="list">${past.map(gameItem).join('')}</ul>` : '<p class="muted">Nothing yet. Your finished nights will show up here.</p>'}
    </div>`;
  document.getElementById('joinForm').addEventListener('submit', async (e) => {
    e.preventDefault();
    const raw = e.target.code.value.trim();
    const code = (raw.match(/([A-Za-z0-9]{6})\/?$/) || [])[1];
    if (!code) return toast('That code looks wrong', true);
    try { await joinAndGo(code.toUpperCase()); } catch (err) { toast(err.message, true); }
  });
  state.poll = setInterval(async () => {
    if (location.hash && location.hash !== '#/') return;
    const fresh = await api('GET', '/api/me').catch(() => null);
    if (fresh && JSON.stringify(fresh.games) !== JSON.stringify(state.me.games) && !isTyping()) viewHome();
  }, 10000);
}

function gameItem(g) {
  const result = g.status === 'live'
    ? `<span class="small muted">Pot ${money(g.pot, g.currency)}</span>`
    : g.myNet != null ? `<b class="${netClass(g.myNet)} num">${signed(g.myNet, g.currency)}</b>` : '';
  return `<li><a class="item" href="#/game/${g.id}">
    <div class="grow"><div class="row" style="gap:6px"><b>${esc(g.name)}</b>
      ${g.status === 'live' ? '<span class="tag pill-live">LIVE</span>' : ''}
      ${g.isAdmin && g.pendingEntries ? `<span class="badge" title="Waiting for your approval">${g.pendingEntries}</span>` : ''}</div>
      <div class="small muted">${esc(fmtDate(g.date))} · ${g.players} players · ${g.isAdmin ? 'you host' : 'host ' + esc(g.adminName)}</div></div>
    ${result}<span class="muted">›</span></a></li>`;
}

// ---------------------------------------------------------------- new game
async function viewNewGame() {
  const last = store.get('pn.lastSetup', { currency: 'ILS', chipValue: 1, buyIns: [50, 100, 200], allowCustom: false });
  const weekday = new Date().toLocaleDateString('en-GB', { weekday: 'long' });
  const s = { ...last, buyIns: last.buyIns.slice() };
  $app.innerHTML = `
    <a class="back" href="#/">‹ Home</a>
    <h1>Open a new table</h1>
    <p class="muted">You'll be the host tonight: you approve buy-ins and you're the only one who can edit or delete entries.</p>
    <form id="newGame" class="stack">
      <div class="card">
        <div class="field"><label>Name</label><input name="name" value="${esc(weekday)} poker" maxlength="40"></div>
        <div class="row">
          <div class="field grow"><label>Date</label><input name="date" type="date" value="${todayISO()}"></div>
          <div class="field grow"><label>Where (optional)</label><input name="location" placeholder="Dan's place" maxlength="60"></div>
        </div>
      </div>
      <div class="card">
        <h3>Currency</h3>
        <div class="seg" id="curSeg">${Object.entries(CURRENCY).map(([k, v]) => `<button type="button" data-cur="${k}">${v.symbol} ${v.label}</button>`).join('')}</div>
        <h3 style="margin-top:16px">Chip value</h3>
        <p class="small muted">How much is one chip worth?</p>
        <div class="seg" id="mulSeg">${MULTIPLIERS.map((m) => `<button type="button" data-mul="${m}">1×${m}</button>`).join('')}
          <button type="button" data-mul="custom">Other</button></div>
        <div class="field hide" id="customMul" style="margin-top:10px"><label>Money per chip</label><input type="number" step="any" min="0.01" inputmode="decimal" name="customMul"></div>
        <p class="small" id="mulHint" style="margin-top:10px"></p>
      </div>
      <div class="card">
        <h3>Entry options</h3>
        <p class="small muted">These become the buy-in buttons every player taps. Amounts are in money.</p>
        <div class="row wrap" id="buyinTags" style="margin-bottom:10px"></div>
        <div class="row"><input id="buyinInput" type="number" step="any" min="0" inputmode="decimal" placeholder="Add amount, e.g. 100" class="grow">
          <button type="button" id="addBuyin" class="sm">Add</button></div>
        <label class="row small" style="margin-top:12px;gap:8px;color:var(--ink-2)">
          <input type="checkbox" name="allowCustom" style="width:auto;min-height:0" ${s.allowCustom ? 'checked' : ''}> Let players request any amount too</label>
      </div>
      <button class="primary block" style="min-height:56px;font-size:18px">Open table & get invite link</button>
    </form>`;
  const form = document.getElementById('newGame');
  const paint = () => {
    form.querySelectorAll('[data-cur]').forEach((b) => b.classList.toggle('on', b.dataset.cur === s.currency));
    const preset = MULTIPLIERS.includes(s.chipValue);
    form.querySelectorAll('[data-mul]').forEach((b) => b.classList.toggle('on', preset ? Number(b.dataset.mul) === s.chipValue : b.dataset.mul === 'custom'));
    document.getElementById('customMul').classList.toggle('hide', preset);
    if (!preset) form.customMul.value = s.chipValue;
    document.getElementById('mulHint').innerHTML = `1 chip = <b>${money(s.chipValue, s.currency)}</b>`;
    document.getElementById('buyinTags').innerHTML = s.buyIns.length
      ? s.buyIns.map((v, i) => `<span class="tag">${money(v, s.currency)} <span class="muted">(${chips(v / s.chipValue)} chips)</span><button type="button" data-rm="${i}" aria-label="Remove">✕</button></span>`).join('')
      : '<span class="small muted">Add at least one option.</span>';
  };
  form.addEventListener('click', (e) => {
    const b = e.target.closest('button'); if (!b) return;
    if (b.dataset.cur) s.currency = b.dataset.cur;
    if (b.dataset.mul) s.chipValue = b.dataset.mul === 'custom' ? (MULTIPLIERS.includes(s.chipValue) ? 10 : s.chipValue) : Number(b.dataset.mul);
    if (b.dataset.rm) s.buyIns.splice(Number(b.dataset.rm), 1);
    if (b.id === 'addBuyin') addBuyin();
    paint();
  });
  const addBuyin = () => {
    const inp = document.getElementById('buyinInput');
    const v = Number(inp.value);
    if (v > 0 && !s.buyIns.includes(v) && s.buyIns.length < 8) { s.buyIns.push(v); s.buyIns.sort((a, b) => a - b); }
    inp.value = ''; paint();
  };
  document.getElementById('buyinInput').addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); addBuyin(); } });
  form.customMul.addEventListener('input', () => { const v = Number(form.customMul.value); if (v > 0) { s.chipValue = v; paint(); } });
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    if (document.getElementById('buyinInput').value) addBuyin();
    s.allowCustom = form.allowCustom.checked;
    try {
      const g = await api('POST', '/api/games', {
        name: form.name.value, date: form.date.value, location: form.location.value,
        currency: s.currency, chipValue: s.chipValue, buyIns: s.buyIns, allowCustom: s.allowCustom,
      });
      store.set('pn.lastSetup', { currency: s.currency, chipValue: s.chipValue, buyIns: s.buyIns, allowCustom: s.allowCustom });
      store.set('pn.justCreated', g.id);
      location.hash = `#/game/${g.id}`;
    } catch (err) { toast(err.message, true); }
  });
  paint();
}

// ---------------------------------------------------------------- game
const inviteLink = (g) => (window.PN_DEMO_SESSION ? `${location.href.split('#')[0]}#/join/${g.code}` : `${location.origin}/j/${g.code}`);
const isTyping = () => {
  const a = document.activeElement;
  return a && ['INPUT', 'TEXTAREA', 'SELECT'].includes(a.tagName) || $dialog.open;
};

function sortedLines(g) {
  // Finished players by net first, then those still playing by money in.
  return g.lines.slice().sort((a, b) => {
    if ((a.net == null) !== (b.net == null)) return a.net == null ? 1 : -1;
    if (a.net != null) return b.net - a.net;
    return b.buyIn - a.buyIn;
  });
}

function standingsText(g) {
  const cur = g.currency;
  const name = (uid) => (g.users[uid] || {}).name || '?';
  const medals = ['🥇', '🥈', '🥉'];
  const lines = sortedLines(g).filter((l) => l.buyIn > 0);
  const out = [];
  out.push(`♠️♥️ *${g.name}* ♣️♦️`);
  out.push(`${fmtDate(g.date)}${g.location ? ' · ' + g.location : ''}`);
  out.push(`${g.status === 'live' ? '🔴 LIVE' : '✅ Final'} · 1 chip = ${money(g.chipValue, cur)} · Pot ${money(g.totals.pot, cur)} (${chips(g.totals.potChips)} chips)`);
  out.push('');
  const done = lines.filter((l) => l.net != null);
  const playing = lines.filter((l) => l.net == null);
  if (done.length) {
    out.push(g.status === 'live' ? '*Cashed out*' : '*Results*');
    done.forEach((l, i) => {
      const m = i < 3 && l.net > 0 ? medals[i] : l.net < 0 ? '🔻' : '▫️';
      out.push(`${m} ${name(l.userId)}  *${signed(l.net, cur)}*  (in ${money(l.buyIn, cur)} → out ${money(l.cashOut, cur)})`);
    });
  }
  if (playing.length) {
    if (done.length) out.push('');
    out.push('*Still playing*');
    for (const l of playing) out.push(`🎲 ${name(l.userId)}  in ${money(l.buyIn, cur)}${l.buyIns > 1 ? ` (${l.buyIns} buy-ins)` : ''}`);
  }
  if (g.settlements.length) {
    out.push('', '*💸 Settle up*');
    for (const t of g.settlements) out.push(`${t.paid ? '✅' : '▪️'} ${name(t.from)} → ${name(t.to)}  ${money(t.amount, cur)}`);
  }
  if (g.status === 'live' && !g.totals.balanced && !g.totals.missingCashouts.length) {
    out.push('', `⚠️ Chips off by ${money(Math.abs(g.totals.difference), cur)}`);
  }
  return out.join('\n');
}

async function viewGame(id, fresh) {
  const g = state.game = fresh || await api('GET', `/api/games/${id}`);
  renderGame(g);
  clearInterval(state.poll);
  state.poll = setInterval(async () => {
    if (location.hash !== `#/game/${id}`) return;
    const next = await api('GET', `/api/games/${id}`).catch(() => null);
    if (!next || next.updatedAt === state.game.updatedAt) return;
    state.game = next;
    if (!isTyping()) renderGame(next);
  }, 3000);
}

function renderGame(g) {
  const me = state.user.id;
  const cur = g.currency;
  const live = g.status === 'live';
  const user = (uid) => g.users[uid] || { name: '?' };
  const mine = g.lines.find((l) => l.userId === me);
  const myPending = g.entries.filter((e) => e.userId === me && e.status === 'pending');
  const pending = g.entries.filter((e) => e.status === 'pending');
  const justCreated = store.get('pn.justCreated', null) === g.id;
  if (justCreated) store.del('pn.justCreated');

  const pendingCard = g.isAdmin && live && pending.length ? `
    <div class="card alert"><div class="row between"><h3>Waiting for you (${pending.length})</h3>
      ${pending.length > 1 ? '<button class="sm primary" data-act="approveAll">Approve all</button>' : ''}</div>
      <ul class="list">${pending.map((e) => `<li class="row">${avatar(user(e.userId))}
        <div class="grow"><b>${esc(user(e.userId).name)}</b><div class="small muted">wants in for <b class="num" style="color:var(--ink)">${money(e.amount, cur)}</b> · ${chips(e.amount / g.chipValue)} chips · ${ago(e.createdAt)}</div></div>
        <button class="sm danger" data-act="reject" data-id="${e.id}" aria-label="Decline">✕</button>
        <button class="sm primary" data-act="approve" data-id="${e.id}">Approve</button></li>`).join('')}</ul></div>` : '';

  const seatCard = mine && live ? `
    <div class="card gold">
      <div class="row between"><h3>Your seat</h3><span class="small muted">In: <b class="num" style="color:var(--ink)">${money(mine.buyIn, cur)}</b> · ${chips(mine.buyIn / g.chipValue)} chips</span></div>
      <p class="small muted">${g.isAdmin ? 'Tap to add chips for yourself.' : 'Tap an amount to ask for chips. The host approves it.'}</p>
      <div class="buyins">${g.buyIns.map((v) => `<button class="primary" data-act="buyin" data-amt="${v}"><span class="amt">${money(v, cur)}</span><span class="chips">${chips(v / g.chipValue)} chips</span></button>`).join('')}
        ${g.allowCustom || g.isAdmin ? '<button data-act="buyinCustom"><span class="amt">＋</span><span class="chips">Other amount</span></button>' : ''}</div>
      ${myPending.length ? `<ul class="list" style="margin-top:10px">${myPending.map((e) => `<li class="row"><span class="grow small">⏳ ${money(e.amount, cur)} waiting for the host</span>
        <button class="sm ghost" data-act="withdraw" data-id="${e.id}">Withdraw</button></li>`).join('')}</ul>` : ''}
      <div class="row" style="margin-top:12px">
        <div class="grow small">Done for the night? ${mine.cashChips != null ? `Your final count: <b>${chips(mine.cashChips)} chips</b> (${money(mine.cashOut, cur)})` : 'Enter your final chip count.'}</div>
        <button class="sm" data-act="cashout" data-uid="${me}">${mine.cashChips != null ? 'Change' : 'Cash out'}</button></div>
    </div>` : '';

  const t = g.totals;
  const totalsCard = `
    <div class="totals" style="margin-bottom:14px">
      <div><div class="v num">${money(t.pot, cur)}</div><div class="k">Pot · ${chips(t.potChips)} chips</div></div>
      <div><div class="v num">${g.lines.filter((l) => l.buyIn > 0).length}<span class="muted" style="font-size:14px">/${g.players.length}</span></div><div class="k">Bought in</div></div>
      <div><div class="v num">${money(t.cashedOut, cur)}</div><div class="k">Cashed out</div></div>
    </div>`;

  const lines = sortedLines(g);
  let rank = 0;
  const standings = `
    <div class="card"><div class="row between"><h3>${live ? 'Standings' : 'Results'}</h3>
      <span class="small muted">1 chip = ${money(g.chipValue, cur)}</span></div>
      <div class="standings">${lines.map((l) => {
        const u = user(l.userId);
        if (l.net != null) rank++;
        const open = state.openPlayer === l.userId;
        const canOpen = g.isAdmin || l.userId === me;
        const entries = g.entries.filter((e) => e.userId === l.userId);
        return `<div class="player">
          <div class="row" ${canOpen ? `data-act="togglePlayer" data-uid="${l.userId}" style="cursor:pointer"` : ''}>
            ${avatar(u)}
            <div class="grow"><b>${esc(u.name)}</b> ${l.userId === g.adminId ? '<span title="Host">👑</span>' : ''} ${l.userId === me ? '<span class="small muted">(you)</span>' : ''}
              <div class="sub num">in ${money(l.buyIn, cur)}${l.buyIns > 1 ? ` · ${l.buyIns} buy-ins` : ''}${l.pending ? ` · ⏳ ${money(l.pending, cur)}` : ''}${l.cashChips != null ? ` · out ${chips(l.cashChips)} chips` : ''}</div></div>
            <div class="net num ${netClass(l.net)}">${l.net != null ? signed(l.net, cur) : l.buyIn ? '<span class="small muted">playing</span>' : '<span class="small muted">—</span>'}</div>
            ${canOpen ? `<span class="muted">${open ? '▾' : '▸'}</span>` : ''}
          </div>
          ${open ? `<div class="player-detail">
            ${entries.length ? `<ul class="list">${entries.map((e) => `<li class="row small">
              <span class="grow">${e.status === 'pending' ? '⏳' : '✅'} ${money(e.amount, cur)} <span class="muted">· ${chips(e.amount / g.chipValue)} chips · ${ago(e.createdAt)}</span></span>
              ${g.isAdmin && live ? `<button class="sm ghost" data-act="editEntry" data-id="${e.id}" data-amt="${e.amount}">Edit</button>
              <button class="sm danger" data-act="deleteEntry" data-id="${e.id}">Delete</button>` : ''}</li>`).join('')}</ul>` : '<p class="small muted">No entries yet.</p>'}
            ${live ? `<div class="row wrap" style="margin-top:10px">
              ${g.isAdmin ? `<button class="sm" data-act="addFor" data-uid="${l.userId}">＋ Add entry</button>` : ''}
              <button class="sm" data-act="cashout" data-uid="${l.userId}">Final chips</button>
              ${g.isAdmin && l.userId !== g.adminId ? `<button class="sm" data-act="makeHost" data-uid="${l.userId}">Make host</button>
              <button class="sm danger" data-act="removePlayer" data-uid="${l.userId}">Remove</button>` : ''}</div>` : ''}
          </div>` : ''}
        </div>`;
      }).join('')}</div>
      ${live && t.missingCashouts.length === 0 && t.pot > 0 && !t.balanced ? `<p class="small" style="color:var(--warn);margin-top:10px">⚠️ Cash-outs are ${t.difference > 0 ? 'over' : 'under'} the pot by ${money(Math.abs(t.difference), cur)} (${chips(Math.abs(t.difference) / g.chipValue)} chips). Recount before ending.</p>` : ''}
    </div>`;

  const shareCard = `
    <div class="card"><h3>Share standings</h3>
      <p class="small muted">Current table as a WhatsApp-ready message.</p>
      <div class="row"><button class="grow" data-act="copyStandings">📋 Copy</button>
      <a class="btn whatsapp grow" target="_blank" rel="noopener" href="${esc(whatsappUrl(standingsText(g)))}">WhatsApp</a></div></div>`;

  const inviteText = `🃏 You're invited to *${g.name}* (${fmtDate(g.date)})${g.location ? ' at ' + g.location : ''}.\nTap to take a seat: ${inviteLink(g)}`;
  const inviteCard = live ? `
    <div class="card ${justCreated ? 'gold' : ''}"><h3>Invite players</h3>
      ${justCreated ? '<p>Your table is open. Send this link to tonight\'s players.</p>' : ''}
      <div class="row"><input readonly value="${esc(inviteLink(g))}" class="grow" onclick="this.select()">
        <button class="sm" data-act="copyInvite">Copy</button></div>
      <div class="row" style="margin-top:8px"><a class="btn whatsapp grow" target="_blank" rel="noopener" href="${esc(whatsappUrl(inviteText))}">Send invite on WhatsApp</a>
        ${navigator.share ? '<button data-act="shareInvite" aria-label="Share">↗</button>' : ''}</div>
      <p class="small muted" style="margin-top:8px">Code: <b style="letter-spacing:.15em">${esc(g.code)}</b></p></div>` : '';

  const settleCard = !live && g.settlements.length ? `
    <div class="card gold"><h3>💸 Settle up</h3>
      <ul class="list">${g.settlements.map((s, i) => {
        const canMark = [s.from, s.to, g.adminId].includes(me);
        return `<li class="row">${avatar(user(s.from))}<span class="muted">→</span>${avatar(user(s.to))}
          <div class="grow"><div><b>${esc(user(s.from).name)}</b> <span class="muted">pays</span> <b>${esc(user(s.to).name)}</b></div>
            <b class="num" style="color:var(--gold)">${money(s.amount, cur)}</b></div>
          ${canMark ? `<button class="sm ${s.paid ? 'primary' : ''}" data-act="paid" data-idx="${i}" data-paid="${s.paid ? 0 : 1}">${s.paid ? '✓ Paid' : 'Mark paid'}</button>` : s.paid ? '<span class="small win">✓ Paid</span>' : ''}</li>`;
      }).join('')}</ul>
      ${t.balanced ? '' : `<p class="small" style="color:var(--warn)">This night was closed with chips off by ${money(Math.abs(t.difference), cur)}, so payments don't fully balance.</p>`}</div>` : '';

  const hostCard = g.isAdmin ? `
    <div class="card"><h3>Host controls</h3>
      ${live ? `<p class="small muted">End the night once everyone has entered their final chips. Stats only count finished nights.</p>
        <button class="primary block" data-act="endGame">🏁 End the night & settle up</button>
        <div class="row wrap" style="margin-top:10px">
          <button class="sm" data-act="editSettings">Edit table</button>
          <button class="sm" data-act="resetInvite">New invite link</button>
          <button class="sm danger" data-act="deleteGame">Delete</button></div>`
      : `<div class="row wrap"><button class="sm" data-act="reopen">Reopen table</button>
          <button class="sm danger" data-act="deleteGame">Delete night</button></div>`}
    </div>` : '';

  $app.innerHTML = `
    <a class="back" href="#/">‹ Home</a>
    <div class="row between" style="align-items:flex-start;margin-bottom:12px">
      <div class="grow"><h1>${esc(g.name)}</h1>
        <p class="muted small">${esc(fmtDate(g.date))}${g.location ? ' · ' + esc(g.location) : ''} · host ${esc(user(g.adminId).name)} · ${esc(CURRENCY[cur].label)}</p></div>
      ${live ? '<span class="tag pill-live">LIVE</span>' : '<span class="tag">Final</span>'}
    </div>
    ${justCreated ? inviteCard : ''}
    ${pendingCard}
    ${seatCard}
    ${totalsCard}
    ${settleCard}
    ${standings}
    ${shareCard}
    ${justCreated ? '' : inviteCard}
    ${hostCard}
    <details class="card"><summary>Activity</summary>
      <ul class="list log" style="margin-top:8px">${g.log.map((x) => `<li>${esc(x.text)} <span class="muted">· ${ago(x.at)}</span></li>`).join('')}</ul></details>`;
}

async function gameAction(method, path, body) {
  const g = state.game;
  const next = await api(method, `/api/games/${g.id}${path}`, body);
  if (next && next.id) { state.game = next; renderGame(next); }
  return next;
}

const actions = {
  async buyin(el) {
    const amt = Number(el.dataset.amt);
    const g = state.game;
    await gameAction('POST', '/entries', { amount: amt });
    toast(g.isAdmin ? `Added ${money(amt, g.currency)}` : 'Sent to the host for approval');
  },
  async buyinCustom() {
    const g = state.game;
    const v = await promptDialog('Other amount', { label: `Amount in ${CURRENCY[g.currency].label}`, type: 'number', okLabel: g.isAdmin ? 'Add' : 'Request' });
    if (v == null || v === '') return;
    await gameAction('POST', '/entries', { amount: Number(v) });
  },
  async addFor(el) {
    const g = state.game;
    const name = (g.users[el.dataset.uid] || {}).name;
    const v = await promptDialog(`Add entry for ${name}`, { label: `Amount in ${CURRENCY[g.currency].label}`, type: 'number', value: g.buyIns[0], okLabel: 'Add' });
    if (v == null || v === '') return;
    await gameAction('POST', '/entries', { amount: Number(v), userId: el.dataset.uid });
  },
  approve: (el) => gameAction('POST', `/entries/${el.dataset.id}/approve`),
  approveAll: () => gameAction('POST', '/entries/approve-all'),
  reject: (el) => gameAction('POST', `/entries/${el.dataset.id}/reject`),
  withdraw: (el) => gameAction('DELETE', `/entries/${el.dataset.id}`),
  async editEntry(el) {
    const v = await promptDialog('Edit entry', { label: `Amount in ${CURRENCY[state.game.currency].label}`, type: 'number', value: el.dataset.amt });
    if (v == null || v === '') return;
    await gameAction('PATCH', `/entries/${el.dataset.id}`, { amount: Number(v) });
  },
  async deleteEntry(el) {
    if (await confirmDialog('Delete this entry?', 'It will be removed from the table.', 'Delete', true)) await gameAction('DELETE', `/entries/${el.dataset.id}`);
  },
  togglePlayer(el) {
    state.openPlayer = state.openPlayer === el.dataset.uid ? null : el.dataset.uid;
    renderGame(state.game);
  },
  async cashout(el) {
    const g = state.game;
    const line = g.lines.find((l) => l.userId === el.dataset.uid);
    const who = el.dataset.uid === state.user.id ? 'your' : `${(g.users[el.dataset.uid] || {}).name}'s`;
    const v = await promptDialog('Final chip count', {
      label: `Count ${who} chips`, type: 'number', value: line && line.cashChips != null ? line.cashChips : '',
      hint: `1 chip = ${money(g.chipValue, g.currency)}. Leave empty to clear.`,
    });
    if (v == null) return;
    await gameAction('PUT', `/cashouts/${el.dataset.uid}`, { chips: v === '' ? null : Number(v) });
  },
  async removePlayer(el) {
    const name = (state.game.users[el.dataset.uid] || {}).name;
    if (await confirmDialog(`Remove ${name}?`, 'Their entries at this table are deleted too.', 'Remove', true)) {
      state.openPlayer = null;
      await gameAction('DELETE', `/players/${el.dataset.uid}`);
    }
  },
  async makeHost(el) {
    const name = (state.game.users[el.dataset.uid] || {}).name;
    if (await confirmDialog(`Make ${name} the host?`, "You'll lose host controls for this table.", 'Hand over')) await gameAction('POST', '/host', { userId: el.dataset.uid });
  },
  async endGame() {
    try { await gameAction('POST', '/end', {}); toast('Night finished. Settle up below.'); }
    catch (e) {
      if (e.data && e.data.code === 'unbalanced') {
        if (await confirmDialog("Chips don't add up", `${e.message}. You can recount, or end anyway and the payments will be off by that amount.`, 'End anyway', true)) {
          await gameAction('POST', '/end', { force: true });
        }
      } else throw e;
    }
  },
  reopen: () => gameAction('POST', '/reopen'),
  paid: (el) => gameAction('POST', `/settlements/${el.dataset.idx}`, { paid: el.dataset.paid === '1' }),
  async deleteGame() {
    if (await confirmDialog('Delete this night?', 'All entries and results are gone for everyone. This cannot be undone.', 'Delete', true)) {
      await api('DELETE', `/api/games/${state.game.id}`);
      location.hash = '#/';
    }
  },
  async resetInvite() {
    if (await confirmDialog('Make a new invite link?', 'The old link stops working. Players already seated stay.', 'New link')) await gameAction('POST', '/invite/reset');
  },
  copyInvite: () => copyText(inviteLink(state.game)),
  shareInvite: () => navigator.share({ title: state.game.name, text: `Join ${state.game.name}`, url: inviteLink(state.game) }).catch(() => {}),
  copyStandings: () => copyText(standingsText(state.game)),
  editSettings: () => editSettings(),
};

async function editSettings() {
  const g = state.game;
  $dialog.innerHTML = `<form method="dialog" id="settings"><h2>Edit table</h2>
    <div class="field"><label>Name</label><input name="name" value="${esc(g.name)}" maxlength="40"></div>
    <div class="row"><div class="field grow"><label>Date</label><input type="date" name="date" value="${esc(g.date)}"></div>
    <div class="field grow"><label>Where</label><input name="location" value="${esc(g.location || '')}" maxlength="60"></div></div>
    <div class="row"><div class="field grow"><label>Currency</label><select name="currency">${Object.entries(CURRENCY).map(([k, v]) => `<option value="${k}" ${k === g.currency ? 'selected' : ''}>${v.symbol} ${v.label}</option>`).join('')}</select></div>
    <div class="field grow"><label>1 chip =</label><input name="chipValue" type="number" step="any" inputmode="decimal" value="${g.chipValue}"></div></div>
    <div class="field"><label>Entry options (comma separated)</label><input name="buyIns" value="${esc(g.buyIns.join(', '))}" inputmode="decimal"></div>
    <label class="row small" style="gap:8px"><input type="checkbox" name="allowCustom" style="width:auto;min-height:0" ${g.allowCustom ? 'checked' : ''}> Players may request any amount</label>
    <div class="row" style="justify-content:flex-end;margin-top:14px"><button value="cancel" class="ghost">Cancel</button><button value="ok" class="primary">Save</button></div></form>`;
  $dialog.onclick = null;
  $dialog.returnValue = '';
  $dialog.onclose = async () => {
    $dialog.onclose = null;
    if ($dialog.returnValue !== 'ok') return;
    const f = document.getElementById('settings');
    try {
      await gameAction('PATCH', '', {
        name: f.name.value, date: f.date.value, location: f.location.value, currency: f.currency.value,
        chipValue: Number(f.chipValue.value), allowCustom: f.allowCustom.checked,
        buyIns: f.buyIns.value.split(/[,\s]+/).filter(Boolean).map(Number),
      });
      toast('Saved');
    } catch (e) { toast(e.message, true); }
  };
  $dialog.showModal();
}

document.addEventListener('click', async (e) => {
  const el = e.target.closest('[data-act]');
  if (!el || !actions[el.dataset.act]) return;
  e.preventDefault();
  if (el.tagName === 'BUTTON') el.disabled = true;
  try { await actions[el.dataset.act](el); }
  catch (err) { toast(err.message, true); }
  finally { if (el.isConnected && el.tagName === 'BUTTON') el.disabled = false; }
});

// ---------------------------------------------------------------- stats
async function viewStats() {
  const data = await api('GET', '/api/stats');
  const pref = store.get('pn.statsCur', null);
  let cur = data.currencies.includes(pref) ? pref : null;
  if (!cur) {
    const counts = {};
    for (const p of data.players) for (const [c, s] of Object.entries(p.byCurrency)) counts[c] = (counts[c] || 0) + s.games;
    cur = Object.keys(counts).sort((a, b) => counts[b] - counts[a])[0];
  }
  if (!cur) {
    $app.innerHTML = `<h1>Stats</h1><div class="card"><p>No finished nights yet.</p>
      <p class="muted small">Once a host ends a night, everyone's results show up here: profit, win rate, streaks and more.</p></div>`;
    return;
  }
  const rows = data.players.filter((p) => p.byCurrency[cur]).map((p) => ({ ...p, s: p.byCurrency[cur] }))
    .sort((a, b) => b.s.net - a.s.net);
  const top = (fn, min = 1) => rows.filter((r) => r.s.games >= min).sort((a, b) => fn(b) - fn(a))[0];
  const fame = [
    ['💰', 'Biggest winner', top((r) => r.s.net), (r) => signed(r.s.net, cur)],
    ['🚀', 'Best single night', top((r) => r.s.best), (r) => signed(r.s.best, cur)],
    ['🎯', 'Best win rate (3+ nights)', top((r) => r.s.winRate, 3), (r) => pct(r.s.winRate)],
    ['🔥', 'Hottest streak now', top((r) => r.s.streak), (r) => (r.s.streak >= 2 ? `${r.s.streak} wins in a row` : null)],
    ['🪑', 'Most nights', top((r) => r.s.games), (r) => `${r.s.games}`],
    ['🎁', 'Most generous', top((r) => -r.s.net), (r) => (r.s.net < 0 ? signed(r.s.net, cur) : null)],
  ].filter(([, , r, f]) => r && f(r));
  $app.innerHTML = `
    <h1>Stats</h1>
    <p class="muted small">Everyone you've sat with. Finished nights only.</p>
    ${data.currencies.length > 1 ? `<div class="seg" style="margin-bottom:14px">${data.currencies.map((c) => `<button data-cur="${c}" class="${c === cur ? 'on' : ''}">${sym(c)} ${CURRENCY[c].label}</button>`).join('')}</div>` : ''}
    <div class="card"><h3>Leaderboard</h3>
      <table class="lb"><thead><tr><th>#</th><th>Player</th><th class="r">Nights</th><th class="r">Win%</th><th class="r">Profit</th></tr></thead>
      <tbody>${rows.map((r, i) => `<tr data-href="#/player/${r.user.id}">
        <td class="muted">${i + 1}</td>
        <td><div class="row" style="gap:8px">${avatar(r.user)}<div><b>${esc(r.user.name)}</b>${r.user.id === state.user.id ? ' <span class="small muted">(you)</span>' : ''}
          <div class="small muted">${r.badges.map((b) => b.icon).join(' ')} avg ${signed(r.s.avg, cur)}</div></div></div></td>
        <td class="r num">${r.s.games}</td><td class="r num">${pct(r.s.winRate)}</td>
        <td class="r num"><b class="${netClass(r.s.net)}">${signed(r.s.net, cur)}</b></td></tr>`).join('')}</tbody></table></div>
    <div class="card"><h3>Hall of fame</h3><ul class="list">${fame.map(([icon, label, r, f]) => `<li class="row">
      <span style="font-size:22px">${icon}</span><div class="grow"><div class="small muted">${label}</div><b>${esc(r.user.name)}</b></div><b class="num">${f(r)}</b></li>`).join('')}</ul></div>`;
  $app.querySelectorAll('[data-cur]').forEach((b) => b.addEventListener('click', () => { store.set('pn.statsCur', b.dataset.cur); viewStats(); }));
  $app.querySelectorAll('tr[data-href]').forEach((tr) => tr.addEventListener('click', () => { location.hash = tr.dataset.href; }));
}

async function viewPlayer(uid) {
  const data = await api('GET', `/api/players/${uid}`);
  const curs = Object.keys(data.stats.byCurrency);
  const pref = store.get('pn.statsCur', null);
  const cur = curs.includes(pref) ? pref : data.stats.primary;
  const s = cur && data.stats.byCurrency[cur];
  const isMe = uid === state.user.id;
  $app.innerHTML = `
    <a class="back" href="#/stats">‹ Stats</a>
    <div class="hero-head">${avatar(data.user, 'lg')}<div><h1 style="margin:0">${esc(data.user.name)}</h1>
      <div class="row wrap" style="gap:6px;margin-top:4px">${data.badges.map((b) => `<span class="tag" title="${esc(b.hint)}">${b.icon} ${esc(b.label)}</span>`).join('')}</div></div></div>
    ${!s ? `<div class="card"><p class="muted">${isMe ? "You haven't" : 'No'} finished nights yet.</p></div>` : `
    ${curs.length > 1 ? `<div class="seg" style="margin-bottom:14px">${curs.map((c) => `<button data-cur="${c}" class="${c === cur ? 'on' : ''}">${sym(c)} ${CURRENCY[c].label}</button>`).join('')}</div>` : ''}
    <div class="card">
      <div class="tiles">
        <div class="tile"><div class="v ${netClass(s.net)}">${signed(s.net, cur)}</div><div class="k">Total profit</div></div>
        <div class="tile"><div class="v">${s.games}</div><div class="k">Nights</div></div>
        <div class="tile"><div class="v">${pct(s.winRate)}</div><div class="k">Winning nights</div></div>
        <div class="tile"><div class="v ${netClass(s.avg)}">${signed(s.avg, cur)}</div><div class="k">Avg per night</div></div>
        <div class="tile"><div class="v ${netClass(s.roi)}">${s.roi > 0 ? '+' : ''}${pct(s.roi)}</div><div class="k">ROI on buy-ins</div></div>
        <div class="tile"><div class="v">${s.streak > 0 ? `🔥 ${s.streak}W` : s.streak < 0 ? `🧊 ${-s.streak}L` : '–'}</div><div class="k">Current streak</div></div>
        <div class="tile"><div class="v ${netClass(s.best)}">${signed(s.best, cur)}</div><div class="k">Best night</div></div>
        <div class="tile"><div class="v ${netClass(s.worst)}">${signed(s.worst, cur)}</div><div class="k">Worst night</div></div>
        <div class="tile"><div class="v">${money(s.totalBuyIn, cur)}</div><div class="k">Total bought in</div></div>
      </div>
    </div>
    <div class="card"><h3>Profit over time</h3>${profitChart(s.results, cur)}</div>
    <div class="card"><h3>Nights</h3><ul class="list">${s.results.slice().reverse().map((r) => `<li><a class="item" href="#/game/${r.gameId}">
      <div class="grow"><b>${esc(r.name)}</b><div class="small muted">${esc(fmtDate(r.date))} · ${r.players} players · in ${money(r.buyIn, cur)}</div></div>
      <b class="num ${netClass(r.net)}">${signed(r.net, cur)}</b></a></li>`).join('')}</ul></div>`}`;
  $app.querySelectorAll('[data-cur]').forEach((b) => b.addEventListener('click', () => { store.set('pn.statsCur', b.dataset.cur); viewPlayer(uid); }));
  wireChart();
}

// Cumulative profit line. One series, so no legend: the card title names it.
function profitChart(results, cur) {
  if (results.length < 2) return '<p class="small muted">Play a couple more nights to see the trend.</p>';
  const W = 520, H = 200, P = { l: 8, r: 8, t: 14, b: 22 };
  let run = 0;
  const pts = [{ v: 0, label: 'Start' }].concat(results.map((r) => { run += r.net; return { v: Math.round(run * 100) / 100, label: `${fmtDate(r.date)} · ${r.name}`, net: r.net }; }));
  const min = Math.min(0, ...pts.map((p) => p.v)), max = Math.max(0, ...pts.map((p) => p.v));
  const span = max - min || 1;
  const x = (i) => P.l + (i * (W - P.l - P.r)) / (pts.length - 1);
  const y = (v) => P.t + ((max - v) * (H - P.t - P.b)) / span;
  const d = pts.map((p, i) => `${i ? 'L' : 'M'}${x(i).toFixed(1)},${y(p.v).toFixed(1)}`).join('');
  const last = pts[pts.length - 1];
  const color = last.v >= 0 ? 'var(--win)' : 'var(--lose)';
  const data = pts.map((p, i) => ({ x: x(i) / W, y: y(p.v) / H, text: `${p.label}${p.net != null ? ` · ${signed(p.net, cur)}` : ''} · total ${signed(p.v, cur)}` }));
  return `<div class="chart" data-points='${esc(JSON.stringify(data))}'>
    <svg viewBox="0 0 ${W} ${H}" role="img" aria-label="Cumulative profit, now ${esc(signed(last.v, cur))}">
      <line x1="${P.l}" x2="${W - P.r}" y1="${y(0)}" y2="${y(0)}" stroke="var(--line)" stroke-width="1" stroke-dasharray="3 4"/>
      <text x="${W - P.r}" y="${y(0) - 4}" fill="var(--ink-3)" font-size="11" text-anchor="end">${sym(cur)}0</text>
      <path d="${d}" fill="none" stroke="${color}" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>
      <circle cx="${x(pts.length - 1)}" cy="${y(last.v)}" r="4" fill="${color}" stroke="var(--card)" stroke-width="2"/>
      <text x="${x(pts.length - 1) - 6}" y="${y(last.v) + (last.v >= 0 ? -8 : 16)}" fill="var(--ink)" font-size="12" font-weight="700" text-anchor="end">${esc(signed(last.v, cur))}</text>
      <line class="cross" x1="0" x2="0" y1="${P.t}" y2="${H - P.b}" stroke="var(--ink-3)" stroke-width="1" opacity="0"/>
      <circle class="dot" r="5" fill="${color}" stroke="var(--card)" stroke-width="2" opacity="0"/>
    </svg><div class="tip"></div></div>`;
}

function wireChart() {
  for (const el of $app.querySelectorAll('.chart[data-points]')) {
    const pts = JSON.parse(el.dataset.points);
    const svg = el.querySelector('svg'), tip = el.querySelector('.tip');
    const cross = svg.querySelector('.cross'), dot = svg.querySelector('.dot');
    const vb = svg.viewBox.baseVal;
    const show = (clientX) => {
      const r = svg.getBoundingClientRect();
      const fx = (clientX - r.left) / r.width;
      let best = 0;
      pts.forEach((p, i) => { if (Math.abs(p.x - fx) < Math.abs(pts[best].x - fx)) best = i; });
      const p = pts[best];
      cross.setAttribute('x1', p.x * vb.width); cross.setAttribute('x2', p.x * vb.width); cross.setAttribute('opacity', 1);
      dot.setAttribute('cx', p.x * vb.width); dot.setAttribute('cy', p.y * vb.height); dot.setAttribute('opacity', 1);
      tip.textContent = p.text;
      tip.style.left = Math.min(Math.max(p.x * r.width, 90), r.width - 90) + 'px';
      tip.style.top = p.y * r.height + 'px';
      tip.style.opacity = 1;
    };
    const hide = () => { tip.style.opacity = 0; cross.setAttribute('opacity', 0); dot.setAttribute('opacity', 0); };
    svg.addEventListener('pointermove', (e) => show(e.clientX));
    svg.addEventListener('pointerdown', (e) => show(e.clientX));
    svg.addEventListener('pointerleave', hide);
  }
}

// ---------------------------------------------------------------- account
async function viewAccount() {
  const COLORS = ['#e4572e', '#29335c', '#f3a712', '#669bbc', '#a8c686', '#8e5572', '#2a9d8f', '#e76f51', '#6a4c93', '#1982c4'];
  const u = state.user;
  $app.innerHTML = `
    <a class="back" href="#/">‹ Home</a>
    <div class="hero-head">${avatar(u, 'lg')}<h1 style="margin:0">Account</h1></div>
    <form class="card" id="nameForm"><div class="field"><label>Name</label><input name="name" value="${esc(u.name)}" maxlength="24"></div>
      <label>Colour</label><div class="row wrap" style="margin-bottom:14px">${COLORS.map((c) => `<button type="button" data-color="${c}" aria-label="colour" style="width:36px;height:36px;min-height:0;padding:0;border-radius:50%;background:${c};${c === u.color ? 'outline:3px solid var(--gold)' : ''}"></button>`).join('')}</div>
      <button class="primary">Save</button></form>
    <form class="card" id="pinForm"><h3>Change PIN</h3>
      <div class="row"><div class="field grow"><label>Current</label><input name="currentPin" class="pin" type="password" inputmode="numeric" maxlength="6" autocomplete="current-password"></div>
      <div class="field grow"><label>New</label><input name="pin" class="pin" type="password" inputmode="numeric" maxlength="6" autocomplete="new-password"></div></div>
      <button>Update PIN</button></form>
    <div class="card"><h3>Install</h3><p class="small muted">On iPhone: Share → Add to Home Screen. On Android: menu → Install app. It then opens like a normal app.</p></div>
    <button class="danger block" id="logout">Log out</button>`;
  let color = u.color;
  $app.querySelectorAll('[data-color]').forEach((b) => b.addEventListener('click', () => {
    color = b.dataset.color;
    $app.querySelectorAll('[data-color]').forEach((x) => { x.style.outline = x === b ? '3px solid var(--gold)' : ''; });
  }));
  document.getElementById('nameForm').addEventListener('submit', async (e) => {
    e.preventDefault();
    try {
      const r = await api('PATCH', '/api/me', { name: e.target.name.value, color });
      state.user = r.user; store.set('pn.user', r.user); store.set('pn.lastName', r.user.name); toast('Saved'); viewAccount();
    } catch (err) { toast(err.message, true); }
  });
  document.getElementById('pinForm').addEventListener('submit', async (e) => {
    e.preventDefault();
    try { await api('PATCH', '/api/me', { currentPin: e.target.currentPin.value, pin: e.target.pin.value }); e.target.reset(); toast('PIN updated'); }
    catch (err) { toast(err.message, true); }
  });
  document.getElementById('logout').addEventListener('click', () => signOut());
}

// ---------------------------------------------------------------- hand checker
const hands = store.get('pn.hands', { hero: [], board: [], villain: [], opponents: 1, slot: 'hero' });

function cardHTML(c, extra = '') {
  if (c == null) return `<span class="pcard empty ${extra}">+</span>`;
  const s = PH.SUITS[PH.suitOf(c)];
  const r = PH.RANKS[PH.rankOf(c)];
  return `<span class="pcard ${s === 'h' || s === 'd' ? 'red' : ''} ${extra}">${r === 'T' ? '10' : r}<small>${PH.SUIT_SYMBOL[s]}</small></span>`;
}

function viewHands() {
  const limits = { hero: 2, board: 5, villain: 2 };
  const used = new Set([...hands.hero, ...hands.board, ...hands.villain]);
  const slotRow = (key, title) => {
    const arr = hands[key];
    const cells = [];
    for (let i = 0; i < limits[key]; i++) {
      const active = hands.slot === key && i === arr.length;
      cells.push(`<span data-slot="${key}" data-i="${i}">${cardHTML(arr[i], active ? 'active' : '')}</span>`);
    }
    return `<div class="row between" style="margin-bottom:6px"><b class="small">${title}</b>
      ${arr.length ? `<button class="sm ghost" data-clear="${key}">Clear</button>` : ''}</div><div class="slots" style="margin-bottom:12px">${cells.join('')}</div>`;
  };
  const deck = [];
  for (const s of [0, 1, 2, 3]) for (let r = 12; r >= 0; r--) {
    const c = r * 4 + s;
    const suit = PH.SUITS[s];
    deck.push(`<button data-card="${c}" class="${suit === 'h' || suit === 'd' ? 'red' : ''}" ${used.has(c) ? 'disabled' : ''}>${PH.RANKS[r] === 'T' ? '10' : PH.RANKS[r]}<span>${PH.SUIT_SYMBOL[suit]}</span></button>`);
  }

  $app.innerHTML = `
    <h1>Hand checker</h1>
    <p class="muted small">Pick your two cards, then the board as it comes. Add an opponent's hand to settle "who was ahead?" debates.</p>
    <div class="card">
      ${slotRow('hero', 'Your hand')}
      ${slotRow('board', 'Board (flop · turn · river)')}
      ${slotRow('villain', "Opponent's hand (optional)")}
      <div class="row between"><span class="small">Players against you</span>
        <div class="row" style="gap:6px"><button class="sm" data-opp="-1">−</button><b class="num" style="min-width:20px;text-align:center">${hands.opponents}</b><button class="sm" data-opp="1">＋</button></div></div>
    </div>
    <div class="card"><div class="deck">${deck.join('')}</div>
      <div class="row" style="margin-top:10px"><button class="sm ghost grow" data-reset>Reset all</button></div></div>
    <div id="handResult"></div>
    <details class="card"><summary>Hand rankings</summary>
      <ol style="margin:10px 0 0;padding-left:22px;line-height:1.8">
        ${PH.CATEGORIES.slice().reverse().map((c, i) => `<li><b>${c === 'Straight Flush' ? 'Straight Flush (Royal = A-high)' : c}</b> <span class="small muted">${['A♠ K♠ Q♠ J♠ 10♠', '9♣ 9♦ 9♥ 9♠', 'K K K 7 7', 'any 5 of one suit', '5 in a row', 'Q Q Q', 'J J 4 4', 'A A', 'nothing: highest card'][i]}</span></li>`).join('')}
      </ol></details>`;

  $app.querySelectorAll('[data-slot]').forEach((el) => el.addEventListener('click', () => {
    const key = el.dataset.slot, i = Number(el.dataset.i);
    if (hands[key][i] != null) hands[key].splice(i, 1); // tap a card to take it back
    hands.slot = key; saveHands(); viewHands();
  }));
  $app.querySelectorAll('[data-card]').forEach((el) => el.addEventListener('click', () => {
    const c = Number(el.dataset.card);
    let key = hands.slot;
    if (hands[key].length >= limits[key]) key = ['hero', 'board', 'villain'].find((k) => hands[k].length < limits[k]);
    if (!key) return;
    hands[key].push(c);
    if (hands[key].length >= limits[key]) hands.slot = key === 'hero' ? 'board' : key;
    else hands.slot = key;
    saveHands(); viewHands();
  }));
  $app.querySelectorAll('[data-clear]').forEach((el) => el.addEventListener('click', () => { hands[el.dataset.clear] = []; hands.slot = el.dataset.clear; saveHands(); viewHands(); }));
  $app.querySelector('[data-reset]').addEventListener('click', () => { hands.hero = []; hands.board = []; hands.villain = []; hands.slot = 'hero'; saveHands(); viewHands(); });
  $app.querySelectorAll('[data-opp]').forEach((el) => el.addEventListener('click', () => {
    hands.opponents = Math.min(8, Math.max(1, hands.opponents + Number(el.dataset.opp)));
    saveHands(); viewHands();
  }));
  renderHandResult();
}
function saveHands() { store.set('pn.hands', hands); }

function renderHandResult() {
  const out = document.getElementById('handResult');
  const { hero, board, villain } = hands;
  if (hero.length < 2) { out.innerHTML = '<div class="card"><p class="muted">Pick your two cards to see how strong they are.</p></div>'; return; }
  if (board.length === 1 || board.length === 2) { out.innerHTML = '<div class="card"><p class="muted">The flop is three cards: add one or two more.</p></div>'; return; }
  const pre = PH.preflopTier(hero);
  const made = board.length ? PH.describe(PH.evaluate(hero.concat(board))) : null;
  const villains = villain.length === 2 ? [villain] : [];
  const street = ['Pre-flop', , , 'Flop', 'Turn', 'River'][board.length];
  out.innerHTML = `<div class="card"><p class="muted">Crunching ${street.toLowerCase()} odds…</p></div>`;
  setTimeout(() => {
    const eq = PH.equity({ hero, board, villains, opponents: Math.max(hands.opponents, villains.length), iterations: board.length === 5 ? 2000 : 6000 });
    const outs = PH.outs(hero, board);
    const vMade = villains.length && board.length ? PH.describe(PH.evaluate(villain.concat(board))) : null;
    const w = eq.win * 100, t = eq.tie * 100, l = eq.lose * 100;
    const label = eq.equity >= 0.65 ? ['💪', 'Strong favourite'] : eq.equity >= 0.5 ? ['👍', 'Slight favourite'] : eq.equity >= 0.3 ? ['🤔', 'Behind but live'] : ['🥶', 'Big underdog'];
    out.innerHTML = `<div class="card">
      <div class="row between"><h3>${street}</h3><span class="small muted">vs ${Math.max(hands.opponents, villains.length)} player${Math.max(hands.opponents, villains.length) > 1 ? 's' : ''}</span></div>
      ${made ? `<h2>${esc(made)}</h2>` : `<h2>${PH.handLabel(hero)} · ${pre.tier}</h2><p class="small muted">Chen score ${pre.chen}/20 · ${esc(pre.note)}</p>`}
      ${vMade ? `<p class="small">Opponent has <b>${esc(vMade)}</b></p>` : ''}
      <p style="margin-top:10px"><span style="font-size:28px;font-weight:800" class="num">${pct(eq.equity)}</span> <span class="muted">to win the pot</span> · ${label[0]} ${label[1]}</p>
      <div class="bar" role="img" aria-label="Win ${pct(eq.win)}, tie ${pct(eq.tie)}, lose ${pct(eq.lose)}">
        <div class="w" style="width:${w}%">${w >= 12 ? 'Win ' + Math.round(w) + '%' : ''}</div>
        ${t >= 0.5 ? `<div class="t" style="width:${t}%">${t >= 12 ? 'Tie ' + Math.round(t) + '%' : ''}</div>` : ''}
        <div class="l" style="width:${l}%">${l >= 12 ? 'Lose ' + Math.round(l) + '%' : ''}</div></div>
      <p class="small muted" style="margin-top:6px">Win ${pct(eq.win)} · Tie ${pct(eq.tie)} · Lose ${pct(eq.lose)}${villains.length ? ` · opponent's share ${pct(eq.villainEquity[0])}` : ''}</p>
      ${outs.length ? `<p class="small" style="margin-top:10px"><b>${outs.length} outs</b> to improve: ${outs.map((c) => PH.RANKS[PH.rankOf(c)] + PH.SUIT_SYMBOL[PH.SUITS[PH.suitOf(c)]]).join(' ')}
        <span class="muted">(≈${Math.min(100, outs.length * (board.length === 3 ? 4 : 2))}% by the river, rule of ${board.length === 3 ? '4' : '2'})</span></p>` : ''}
      ${board.length < 5 ? `<h3 style="margin-top:14px">Where your hand ends up</h3>
        <div class="dist">${eq.categories.map((p, i) => ({ p, i })).filter((x) => x.p >= 0.005).reverse().map(({ p, i }) => `
          <span>${PH.CATEGORIES[i]}</span><div class="track"><div class="fill" style="width:${(p * 100).toFixed(1)}%"></div></div><span class="num" style="text-align:right">${pct(p)}</span>`).join('')}</div>` : ''}
      <p class="small muted" style="margin-top:10px">Simulated over ${eq.iterations.toLocaleString()} random run-outs.</p>
    </div>`;
  }, 20);
}

// ---------------------------------------------------------------- blinds timer
const DEFAULT_LEVELS = [[1, 2], [2, 4], [3, 6], [5, 10], [10, 20], [15, 30], [25, 50], [50, 100], [75, 150], [100, 200], [150, 300], [200, 400]];
const timer = store.get('pn.timer', { minutes: 15, level: 0, running: false, endsAt: null, remaining: 15 * 60 * 1000, levels: DEFAULT_LEVELS });
let timerTick = null, wakeLock = null;
const saveTimer = () => store.set('pn.timer', timer);
const timeLeft = () => (timer.running ? Math.max(0, timer.endsAt - Date.now()) : timer.remaining);

function beep() {
  try {
    const ctx = new (window.AudioContext || window.webkitAudioContext)();
    [0, 0.25, 0.5].forEach((t) => {
      const o = ctx.createOscillator(), g = ctx.createGain();
      o.frequency.value = 880; o.connect(g); g.connect(ctx.destination);
      g.gain.setValueAtTime(0.25, ctx.currentTime + t); g.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + t + 0.2);
      o.start(ctx.currentTime + t); o.stop(ctx.currentTime + t + 0.22);
    });
  } catch { /* no audio */ }
  if (navigator.vibrate) navigator.vibrate([200, 100, 200]);
}

function setLevel(i) {
  timer.level = Math.max(0, Math.min(timer.levels.length - 1, i));
  timer.remaining = timer.minutes * 60000;
  if (timer.running) timer.endsAt = Date.now() + timer.remaining;
  saveTimer();
}

function viewTimer() {
  const lv = timer.levels[timer.level], next = timer.levels[timer.level + 1];
  $app.innerHTML = `
    <h1>Blinds timer</h1>
    <div class="card center">
      <p class="muted">Level ${timer.level + 1} of ${timer.levels.length}</p>
      <div class="timer-blinds num">${lv[0]} / ${lv[1]}</div>
      <div class="timer-clock" id="clock"></div>
      <p class="small muted">${next ? `Next: ${next[0]} / ${next[1]}` : 'Final level'}</p>
      <div class="row" style="margin-top:12px">
        <button data-t="prev" aria-label="Previous level">⏮</button>
        <button class="primary grow" data-t="toggle" style="min-height:56px;font-size:18px">${timer.running ? 'Pause' : 'Start'}</button>
        <button data-t="next" aria-label="Next level">⏭</button></div>
    </div>
    <div class="card">
      <div class="row between"><span>Minutes per level</span>
        <div class="row" style="gap:6px"><button class="sm" data-t="minus">−</button><b class="num" style="min-width:28px;text-align:center">${timer.minutes}</b><button class="sm" data-t="plus">＋</button></div></div>
      <details style="margin-top:12px"><summary>Blind levels</summary>
        <div class="field" style="margin-top:8px"><label>One level per line, small/big</label>
        <textarea id="levels" rows="8">${timer.levels.map((l) => l.join('/')).join('\n')}</textarea></div>
        <div class="row"><button class="sm" data-t="saveLevels">Save levels</button><button class="sm ghost" data-t="defaults">Defaults</button></div></details>
      <p class="small muted" style="margin-top:10px">Keeps the screen awake while running and beeps when blinds go up.</p>
    </div>`;
  const paint = () => {
    const ms = timeLeft();
    const el = document.getElementById('clock');
    if (!el) { clearInterval(timerTick); return; }
    el.textContent = `${Math.floor(ms / 60000)}:${String(Math.floor(ms / 1000) % 60).padStart(2, '0')}`;
    if (timer.running && ms <= 0) {
      beep();
      if (timer.level < timer.levels.length - 1) { setLevel(timer.level + 1); viewTimer(); }
      else { timer.running = false; timer.remaining = 0; saveTimer(); viewTimer(); }
    }
  };
  clearInterval(timerTick);
  timerTick = setInterval(paint, 250);
  paint();
  $app.querySelectorAll('[data-t]').forEach((b) => b.addEventListener('click', async () => {
    const a = b.dataset.t;
    if (a === 'toggle') {
      if (timer.running) { timer.remaining = timeLeft(); timer.running = false; if (wakeLock) wakeLock.release().catch(() => {}); }
      else {
        if (timer.remaining <= 0) timer.remaining = timer.minutes * 60000;
        timer.endsAt = Date.now() + timer.remaining; timer.running = true;
        try { wakeLock = await navigator.wakeLock.request('screen'); } catch { /* unsupported */ }
      }
      saveTimer();
    }
    if (a === 'next') setLevel(timer.level + 1);
    if (a === 'prev') setLevel(timer.level - 1);
    if (a === 'plus' || a === 'minus') {
      timer.minutes = Math.max(1, Math.min(90, timer.minutes + (a === 'plus' ? 1 : -1)));
      if (!timer.running) timer.remaining = timer.minutes * 60000;
      saveTimer();
    }
    if (a === 'saveLevels' || a === 'defaults') {
      const parsed = a === 'defaults' ? DEFAULT_LEVELS : document.getElementById('levels').value.split('\n')
        .map((line) => line.split(/[/\s,-]+/).map(Number).filter((n) => n > 0)).filter((p) => p.length >= 2).map((p) => [p[0], p[1]]);
      if (!parsed.length) return toast('Add at least one level like 5/10', true);
      timer.levels = parsed; timer.level = Math.min(timer.level, parsed.length - 1); saveTimer(); toast('Levels saved');
    }
    viewTimer();
  }));
}

// ---------------------------------------------------------------- boot
window.PN = { state, store, router };
router();
