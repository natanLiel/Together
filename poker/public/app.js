/* ערב פוקר — single-page app, Hebrew and right-to-left. No framework; views are template strings. */
'use strict';

const $app = document.getElementById('app');
const $tabs = document.getElementById('tabs');
const $dialog = document.getElementById('dialog');
const PH = window.PokerHand;

const CURRENCY = {
  ILS: { symbol: '₪', label: 'ש״ח' },
  USD: { symbol: '$', label: 'דולר' },
  EUR: { symbol: '€', label: 'יורו' },
  GBP: { symbol: '£', label: 'ליש״ט' },
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
// Amounts and percentages are wrapped in left-to-right isolates (U+2066…U+2069)
// so "+₪150" and "67%" keep their order inside Hebrew text, WhatsApp included.
const ltr = (s) => `\u2066${s}\u2069`;
const amount = (n, cur, plus) => `${n < 0 ? '−' : plus && n > 0 ? '+' : ''}${sym(cur)}${nf.format(Math.abs(n))}`;
const money = (n, cur) => ltr(amount(n, cur));
const signed = (n, cur) => ltr(amount(n, cur, true));
const chips = (n) => nf.format(n);
const pct = (x) => ltr(`${Math.round(x * 100)}%`);
const netClass = (n) => (n > 0 ? 'win' : n < 0 ? 'lose' : '');
const initials = (name) => String(name || '?').split(' ').map((w) => w[0]).join('').slice(0, 2).toUpperCase();
const avatar = (u, cls = '') => `<span class="avatar ${cls}" style="background:${esc(u && u.color || '#555')}">${esc(initials(u && u.name))}</span>`;
const fmtDate = (d) => new Date(d + 'T12:00:00').toLocaleDateString('he-IL', { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' });
const ago = (t) => {
  const s = Math.round((Date.now() - t) / 1000);
  if (s < 60) return 'עכשיו';
  if (s < 3600) return `לפני ${Math.floor(s / 60)} דק׳`;
  if (s < 86400) return `לפני ${Math.floor(s / 3600)} שע׳`;
  return new Date(t).toLocaleDateString('he-IL', { day: 'numeric', month: 'short' });
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
  if (!res.ok) { const e = new Error(data.error || 'משהו השתבש'); e.status = res.status; e.data = data; throw e; }
  return data;
}

async function copyText(text) {
  try { await navigator.clipboard.writeText(text); }
  catch {
    const ta = document.createElement('textarea');
    ta.value = text; document.body.appendChild(ta); ta.select();
    document.execCommand('copy'); ta.remove();
  }
  toast('הועתק');
}
const whatsappUrl = (text) => 'https://wa.me/?text=' + encodeURIComponent(text);

function confirmDialog(title, body, okLabel = 'אישור', danger = false) {
  return new Promise((resolve) => {
    $dialog.innerHTML = `<h2>${esc(title)}</h2><p class="muted">${esc(body)}</p>
      <div class="row" style="justify-content:flex-end;margin-top:14px">
        <button data-r="0" class="ghost">ביטול</button>
        <button data-r="1" class="${danger ? 'danger' : 'primary'}">${esc(okLabel)}</button></div>`;
    $dialog.onclick = (e) => {
      const b = e.target.closest('[data-r]');
      if (b) { $dialog.close(); resolve(b.dataset.r === '1'); }
    };
    $dialog.oncancel = () => resolve(false);
    $dialog.showModal();
  });
}

function promptDialog(title, { label = '', value = '', type = 'text', okLabel = 'שמירה', hint = '' } = {}) {
  return new Promise((resolve) => {
    $dialog.innerHTML = `<form method="dialog"><h2>${esc(title)}</h2>
      <div class="field"><label>${esc(label)}</label>
      <input name="v" type="${type}" inputmode="${type === 'number' ? 'decimal' : 'text'}" step="any" value="${esc(value)}" autofocus></div>
      ${hint ? `<p class="small muted">${esc(hint)}</p>` : ''}
      <div class="row" style="justify-content:flex-end">
        <button value="cancel" class="ghost">ביטול</button><button value="ok" class="primary">${esc(okLabel)}</button></div></form>`;
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
  catch (e) { $app.innerHTML = `<div class="card"><h2>אופס.</h2><p>${esc(e.message)}</p><a class="btn" href="#/">לדף הבית</a></div>`; }
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
      <h1>ערב פוקר</h1>
      <p class="muted">כניסות, טבלה וזכויות התרברבות למשחק הבית שלכם.</p>
    </div>
    ${invite ? `<div class="card gold"><h3>הוזמנתם</h3>
      <h2>${esc(invite.name)}</h2>
      <p class="muted">${esc(fmtDate(invite.date))} · מארח: ${esc(invite.host)}${invite.location ? ' · ' + esc(invite.location) : ''}</p>
      <p class="small">התחברו, או בחרו שם וקוד כדי לתפוס מקום.</p></div>` : ''}
    <form class="card" id="auth">
      <div class="seg" style="margin-bottom:14px">
        <button type="button" data-mode="login" class="on">יש לי חשבון</button>
        <button type="button" data-mode="signup">חשבון חדש</button>
      </div>
      <div class="field"><label for="name">השם שלכם</label>
        <input id="name" name="name" autocomplete="username" value="${esc(saved)}" placeholder="למשל: דני כ." required maxlength="24"></div>
      <div class="field"><label for="pin">קוד (4–6 ספרות)</label>
        <input id="pin" name="pin" class="pin" type="password" inputmode="numeric" pattern="[0-9]*" autocomplete="current-password" minlength="4" maxlength="6" required></div>
      <button class="primary block" id="authBtn">כניסה</button>
      <p class="small muted center" style="margin-top:10px" id="authHint">החברים רואים את השם שלכם בשולחן, אז בחרו שם שהם מכירים.</p>
    </form>
    <div class="row" style="justify-content:center;gap:18px">
      <a href="#/hands">🃏 בודק ידיים</a><a href="#/timer">⏱️ שעון בליינדים</a>
    </div>`;
  let mode = 'login';
  const form = document.getElementById('auth');
  form.querySelectorAll('[data-mode]').forEach((b) => b.addEventListener('click', () => {
    mode = b.dataset.mode;
    form.querySelectorAll('[data-mode]').forEach((x) => x.classList.toggle('on', x === b));
    document.getElementById('authBtn').textContent = mode === 'login' ? 'כניסה' : 'יצירת חשבון';
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
  catch (e) { $app.innerHTML = `<div class="card"><h2>אי אפשר להצטרף</h2><p>${esc(e.message)}</p><a class="btn" href="#/">לדף הבית</a></div>`; }
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
      <div class="grow"><p class="muted small" style="margin:0">ברוכים השבים</p><h1 style="margin:0">${esc(me.user.name)}</h1></div>
      <a href="#/account" class="btn icon-btn" aria-label="חשבון">⚙️</a>
    </div>
    ${prim ? `<a class="card" href="#/player/${me.user.id}" style="display:block;color:inherit;text-decoration:none">
      <div class="row between"><h3>המאזן שלכם</h3><span class="small muted">מאז ומעולם · ${esc(CURRENCY[cur].label)} ›</span></div>
      <div class="tiles">
        <div class="tile"><div class="v ${netClass(prim.net)}">${signed(prim.net, cur)}</div><div class="k">רווח</div></div>
        <div class="tile"><div class="v">${prim.games}</div><div class="k">ערבים</div></div>
        <div class="tile"><div class="v">${pct(prim.winRate)}</div><div class="k">ערבים ברווח</div></div>
      </div>
      ${me.badges.length ? `<div class="row wrap" style="margin-top:10px">${me.badges.map((b) => `<span class="tag" title="${esc(b.hint)}">${b.icon} ${esc(b.label)}</span>`).join('')}</div>` : ''}
    </a>` : ''}
    <a class="btn primary block" href="#/new" style="min-height:56px;font-size:18px;margin-bottom:14px">＋ פתיחת שולחן חדש</a>
    ${live.length ? `<div class="card"><h3>שולחנות פעילים</h3><ul class="list">${live.map(gameItem).join('')}</ul></div>` : ''}
    <form class="card" id="joinForm">
      <h3>קיבלתם קוד הזמנה?</h3>
      <div class="row"><input name="code" placeholder="למשל K7Q2XM" autocapitalize="characters" dir="ltr" maxlength="12" class="grow">
      <button class="sm">הצטרפות</button></div>
    </form>
    <div class="card"><h3>ערבים קודמים</h3>
      ${past.length ? `<ul class="list">${past.map(gameItem).join('')}</ul>` : '<p class="muted">עדיין אין. ערבים שנסגרו יופיעו כאן.</p>'}
    </div>`;
  document.getElementById('joinForm').addEventListener('submit', async (e) => {
    e.preventDefault();
    const raw = e.target.code.value.trim();
    const code = (raw.match(/([A-Za-z0-9]{6})\/?$/) || [])[1];
    if (!code) return toast('הקוד הזה לא נראה נכון', true);
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
    ? `<span class="small muted">קופה ${money(g.pot, g.currency)}</span>`
    : g.myNet != null ? `<b class="${netClass(g.myNet)} num">${signed(g.myNet, g.currency)}</b>` : '';
  return `<li><a class="item" href="#/game/${g.id}">
    <div class="grow"><div class="row" style="gap:6px"><b>${esc(g.name)}</b>
      ${g.status === 'live' ? '<span class="tag pill-live">בשידור חי</span>' : ''}
      ${g.isAdmin && g.pendingEntries ? `<span class="badge" title="מחכה לאישור שלכם">${g.pendingEntries}</span>` : ''}</div>
      <div class="small muted">${esc(fmtDate(g.date))} · ${g.players} שחקנים · ${g.isAdmin ? 'אתם מארחים' : 'מארח: ' + esc(g.adminName)}</div></div>
    ${result}<span class="muted">›</span></a></li>`;
}

// ---------------------------------------------------------------- new game
async function viewNewGame() {
  const last = store.get('pn.lastSetup', { currency: 'ILS', chipValue: 1, buyIns: [50, 100, 200], allowCustom: false });
  const weekday = new Date().toLocaleDateString('he-IL', { weekday: 'long' });
  const s = { ...last, buyIns: last.buyIns.slice() };
  $app.innerHTML = `
    <a class="back" href="#/">‹ בית</a>
    <h1>פתיחת שולחן חדש</h1>
    <p class="muted">הערב אתם המארחים: אתם מאשרים כניסות, ורק אתם יכולים לערוך או למחוק אותן.</p>
    <form id="newGame" class="stack">
      <div class="card">
        <div class="field"><label>שם הערב</label><input name="name" value="פוקר ${esc(weekday)}" maxlength="40"></div>
        <div class="row">
          <div class="field grow"><label>תאריך</label><input name="date" type="date" value="${todayISO()}"></div>
          <div class="field grow"><label>איפה (לא חובה)</label><input name="location" placeholder="אצל דני" maxlength="60"></div>
        </div>
      </div>
      <div class="card">
        <h3>מטבע</h3>
        <div class="seg" id="curSeg">${Object.entries(CURRENCY).map(([k, v]) => `<button type="button" data-cur="${k}">${v.symbol} ${v.label}</button>`).join('')}</div>
        <h3 style="margin-top:16px">שווי ז׳יטון</h3>
        <p class="small muted">כמה שווה ז׳יטון אחד?</p>
        <div class="seg" id="mulSeg">${MULTIPLIERS.map((m) => `<button type="button" data-mul="${m}">1×${m}</button>`).join('')}
          <button type="button" data-mul="custom">אחר</button></div>
        <div class="field hide" id="customMul" style="margin-top:10px"><label>כסף לכל ז׳יטון</label><input type="number" step="any" min="0.01" inputmode="decimal" name="customMul"></div>
        <p class="small" id="mulHint" style="margin-top:10px"></p>
      </div>
      <div class="card">
        <h3>סכומי כניסה</h3>
        <p class="small muted">אלה יהיו כפתורי הכניסה שכל שחקן לוחץ עליהם. הסכומים בכסף.</p>
        <div class="row wrap" id="buyinTags" style="margin-bottom:10px"></div>
        <div class="row"><input id="buyinInput" type="number" step="any" min="0" inputmode="decimal" placeholder="הוסיפו סכום, למשל 100" class="grow">
          <button type="button" id="addBuyin" class="sm">הוספה</button></div>
        <label class="row small" style="margin-top:12px;gap:8px;color:var(--ink-2)">
          <input type="checkbox" name="allowCustom" style="width:auto;min-height:0" ${s.allowCustom ? 'checked' : ''}> לאפשר לשחקנים לבקש גם סכום אחר</label>
      </div>
      <button class="primary block" style="min-height:56px;font-size:18px">פתיחת השולחן וקבלת קישור הזמנה</button>
    </form>`;
  const form = document.getElementById('newGame');
  const paint = () => {
    form.querySelectorAll('[data-cur]').forEach((b) => b.classList.toggle('on', b.dataset.cur === s.currency));
    const preset = MULTIPLIERS.includes(s.chipValue);
    form.querySelectorAll('[data-mul]').forEach((b) => b.classList.toggle('on', preset ? Number(b.dataset.mul) === s.chipValue : b.dataset.mul === 'custom'));
    document.getElementById('customMul').classList.toggle('hide', preset);
    if (!preset) form.customMul.value = s.chipValue;
    document.getElementById('mulHint').innerHTML = `ז׳יטון אחד = <b>${money(s.chipValue, s.currency)}</b>`;
    document.getElementById('buyinTags').innerHTML = s.buyIns.length
      ? s.buyIns.map((v, i) => `<span class="tag">${money(v, s.currency)} <span class="muted">(${chips(v / s.chipValue)} ז׳יטונים)</span><button type="button" data-rm="${i}" aria-label="הסרה">✕</button></span>`).join('')
      : '<span class="small muted">הוסיפו לפחות סכום אחד.</span>';
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
  out.push(`${g.status === 'live' ? '🔴 בשידור חי' : '✅ תוצאות סופיות'} · ז׳יטון = ${money(g.chipValue, cur)} · קופה ${money(g.totals.pot, cur)} (${chips(g.totals.potChips)} ז׳יטונים)`);
  out.push('');
  const done = lines.filter((l) => l.net != null);
  const playing = lines.filter((l) => l.net == null);
  if (done.length) {
    out.push(g.status === 'live' ? '*יצאו*' : '*תוצאות*');
    done.forEach((l, i) => {
      const m = i < 3 && l.net > 0 ? medals[i] : l.net < 0 ? '🔻' : '▫️';
      out.push(`${m} ${name(l.userId)}  *${signed(l.net, cur)}*  (כניסה ${money(l.buyIn, cur)}, יציאה ${money(l.cashOut, cur)})`);
    });
  }
  if (playing.length) {
    if (done.length) out.push('');
    out.push('*עדיין משחקים*');
    for (const l of playing) out.push(`🎲 ${name(l.userId)}  כניסה ${money(l.buyIn, cur)}${l.buyIns > 1 ? ` (${l.buyIns} כניסות)` : ''}`);
  }
  if (g.settlements.length) {
    out.push('', '*💸 התחשבנות*');
    for (const t of g.settlements) out.push(`${t.paid ? '✅' : '▪️'} ${name(t.from)} ← ${name(t.to)}  ${money(t.amount, cur)}`);
  }
  if (g.status === 'live' && !g.totals.balanced && !g.totals.missingCashouts.length) {
    out.push('', `⚠️ הז׳יטונים לא מסתדרים, פער של ${money(Math.abs(g.totals.difference), cur)}`);
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
    <div class="card alert"><div class="row between"><h3>מחכים לאישור שלכם (${pending.length})</h3>
      ${pending.length > 1 ? '<button class="sm primary" data-act="approveAll">לאשר הכול</button>' : ''}</div>
      <ul class="list">${pending.map((e) => `<li class="row">${avatar(user(e.userId))}
        <div class="grow"><b>${esc(user(e.userId).name)}</b><div class="small muted">רוצה להיכנס ב־<b class="num" style="color:var(--ink)">${money(e.amount, cur)}</b> · ${chips(e.amount / g.chipValue)} ז׳יטונים · ${ago(e.createdAt)}</div></div>
        <button class="sm danger" data-act="reject" data-id="${e.id}" aria-label="דחייה">✕</button>
        <button class="sm primary" data-act="approve" data-id="${e.id}">אישור</button></li>`).join('')}</ul></div>` : '';

  const seatCard = mine && live ? `
    <div class="card gold">
      <div class="row between"><h3>המקום שלכם</h3><span class="small muted">בפנים: <b class="num" style="color:var(--ink)">${money(mine.buyIn, cur)}</b> · ${chips(mine.buyIn / g.chipValue)} ז׳יטונים</span></div>
      <p class="small muted">${g.isAdmin ? 'לחצו כדי להוסיף לעצמכם ז׳יטונים.' : 'לחצו על סכום כדי לבקש ז׳יטונים. המארח מאשר.'}</p>
      <div class="buyins">${g.buyIns.map((v) => `<button class="primary" data-act="buyin" data-amt="${v}"><span class="amt">${money(v, cur)}</span><span class="chips">${chips(v / g.chipValue)} ז׳יטונים</span></button>`).join('')}
        ${g.allowCustom || g.isAdmin ? '<button data-act="buyinCustom"><span class="amt">＋</span><span class="chips">סכום אחר</span></button>' : ''}</div>
      ${myPending.length ? `<ul class="list" style="margin-top:10px">${myPending.map((e) => `<li class="row"><span class="grow small">⏳ ${money(e.amount, cur)} מחכה לאישור המארח</span>
        <button class="sm ghost" data-act="withdraw" data-id="${e.id}">ביטול</button></li>`).join('')}</ul>` : ''}
      <div class="row" style="margin-top:12px">
        <div class="grow small">סיימתם להערב? ${mine.cashChips != null ? `הספירה הסופית שלכם: <b>${chips(mine.cashChips)} ז׳יטונים</b> (${money(mine.cashOut, cur)})` : 'הזינו את ספירת הז׳יטונים הסופית.'}</div>
        <button class="sm" data-act="cashout" data-uid="${me}">${mine.cashChips != null ? 'שינוי' : 'יציאה'}</button></div>
    </div>` : '';

  const t = g.totals;
  const totalsCard = `
    <div class="totals" style="margin-bottom:14px">
      <div><div class="v num">${money(t.pot, cur)}</div><div class="k">קופה · ${chips(t.potChips)} ז׳יטונים</div></div>
      <div><div class="v num">${g.lines.filter((l) => l.buyIn > 0).length}<span class="muted" style="font-size:14px">/${g.players.length}</span></div><div class="k">נכנסו</div></div>
      <div><div class="v num">${money(t.cashedOut, cur)}</div><div class="k">יצאו</div></div>
    </div>`;

  const lines = sortedLines(g);
  let rank = 0;
  const standings = `
    <div class="card"><div class="row between"><h3>${live ? 'טבלה' : 'תוצאות'}</h3>
      <span class="small muted">ז׳יטון = ${money(g.chipValue, cur)}</span></div>
      <div class="standings">${lines.map((l) => {
        const u = user(l.userId);
        if (l.net != null) rank++;
        const open = state.openPlayer === l.userId;
        const canOpen = g.isAdmin || l.userId === me;
        const entries = g.entries.filter((e) => e.userId === l.userId);
        return `<div class="player">
          <div class="row" ${canOpen ? `data-act="togglePlayer" data-uid="${l.userId}" style="cursor:pointer"` : ''}>
            ${avatar(u)}
            <div class="grow"><b>${esc(u.name)}</b> ${l.userId === g.adminId ? '<span title="מארח">👑</span>' : ''} ${l.userId === me ? '<span class="small muted">(אתם)</span>' : ''}
              <div class="sub num">כניסה ${money(l.buyIn, cur)}${l.buyIns > 1 ? ` · ${l.buyIns} כניסות` : ''}${l.pending ? ` · ⏳ ${money(l.pending, cur)}` : ''}${l.cashChips != null ? ` · יציאה ${chips(l.cashChips)} ז׳יטונים` : ''}</div></div>
            <div class="net num ${netClass(l.net)}">${l.net != null ? signed(l.net, cur) : l.buyIn ? '<span class="small muted">במשחק</span>' : '<span class="small muted">—</span>'}</div>
            ${canOpen ? `<span class="muted">${open ? '▾' : '◂'}</span>` : ''}
          </div>
          ${open ? `<div class="player-detail">
            ${entries.length ? `<ul class="list">${entries.map((e) => `<li class="row small">
              <span class="grow">${e.status === 'pending' ? '⏳' : '✅'} ${money(e.amount, cur)} <span class="muted">· ${chips(e.amount / g.chipValue)} ז׳יטונים · ${ago(e.createdAt)}</span></span>
              ${g.isAdmin && live ? `<button class="sm ghost" data-act="editEntry" data-id="${e.id}" data-amt="${e.amount}">עריכה</button>
              <button class="sm danger" data-act="deleteEntry" data-id="${e.id}">מחיקה</button>` : ''}</li>`).join('')}</ul>` : '<p class="small muted">עדיין אין כניסות.</p>'}
            ${live ? `<div class="row wrap" style="margin-top:10px">
              ${g.isAdmin ? `<button class="sm" data-act="addFor" data-uid="${l.userId}">＋ הוספת כניסה</button>` : ''}
              <button class="sm" data-act="cashout" data-uid="${l.userId}">ספירה סופית</button>
              ${g.isAdmin && l.userId !== g.adminId ? `<button class="sm" data-act="makeHost" data-uid="${l.userId}">להפוך למארח</button>
              <button class="sm danger" data-act="removePlayer" data-uid="${l.userId}">הוצאה</button>` : ''}</div>` : ''}
          </div>` : ''}
        </div>`;
      }).join('')}</div>
      ${live && t.missingCashouts.length === 0 && t.pot > 0 && !t.balanced ? `<p class="small" style="color:var(--warn);margin-top:10px">⚠️ היציאות ${t.difference > 0 ? 'גבוהות' : 'נמוכות'} מהקופה ב־${money(Math.abs(t.difference), cur)} (${chips(Math.abs(t.difference) / g.chipValue)} ז׳יטונים). כדאי לספור שוב לפני הסגירה.</p>` : ''}
    </div>`;

  const shareCard = `
    <div class="card"><h3>שיתוף הטבלה</h3>
      <p class="small muted">הטבלה הנוכחית כהודעה מוכנה לוואטסאפ.</p>
      <div class="row"><button class="grow" data-act="copyStandings">📋 העתקה</button>
      <a class="btn whatsapp grow" target="_blank" rel="noopener" href="${esc(whatsappUrl(standingsText(g)))}">וואטסאפ</a></div></div>`;

  const inviteText = `🃏 מוזמנים ל*${g.name}* (${fmtDate(g.date)})${g.location ? ', ' + g.location : ''}.\nלחצו כדי לתפוס מקום: ${inviteLink(g)}`;
  const inviteCard = live ? `
    <div class="card ${justCreated ? 'gold' : ''}"><h3>הזמנת שחקנים</h3>
      ${justCreated ? '<p>השולחן פתוח. שלחו את הקישור לשחקנים של הערב.</p>' : ''}
      <div class="row"><input readonly dir="ltr" value="${esc(inviteLink(g))}" class="grow" onclick="this.select()">
        <button class="sm" data-act="copyInvite">העתקה</button></div>
      <div class="row" style="margin-top:8px"><a class="btn whatsapp grow" target="_blank" rel="noopener" href="${esc(whatsappUrl(inviteText))}">שליחת הזמנה בוואטסאפ</a>
        ${navigator.share ? '<button data-act="shareInvite" aria-label="שיתוף">↗</button>' : ''}</div>
      <p class="small muted" style="margin-top:8px">קוד: <b dir="ltr" style="letter-spacing:.15em">${esc(g.code)}</b></p></div>` : '';

  const settleCard = !live && g.settlements.length ? `
    <div class="card gold"><h3>💸 התחשבנות</h3>
      <ul class="list">${g.settlements.map((s, i) => {
        const canMark = [s.from, s.to, g.adminId].includes(me);
        return `<li class="row">${avatar(user(s.from))}<span class="muted">←</span>${avatar(user(s.to))}
          <div class="grow"><div><span class="muted">תשלום מ</span><b>${esc(user(s.from).name)}</b> <span class="muted">ל</span><b>${esc(user(s.to).name)}</b></div>
            <b class="num" style="color:var(--gold)">${money(s.amount, cur)}</b></div>
          ${canMark ? `<button class="sm ${s.paid ? 'primary' : ''}" data-act="paid" data-idx="${i}" data-paid="${s.paid ? 0 : 1}">${s.paid ? '✓ שולם' : 'סימון ששולם'}</button>` : s.paid ? '<span class="small win">✓ שולם</span>' : ''}</li>`;
      }).join('')}</ul>
      ${t.balanced ? '' : `<p class="small" style="color:var(--warn)">הערב נסגר עם פער של ${money(Math.abs(t.difference), cur)} בז׳יטונים, ולכן התשלומים לא מתאזנים לגמרי.</p>`}</div>` : '';

  const hostCard = g.isAdmin ? `
    <div class="card"><h3>ניהול השולחן</h3>
      ${live ? `<p class="small muted">סגרו את הערב אחרי שכולם הזינו ספירה סופית. הסטטיסטיקה סופרת רק ערבים סגורים.</p>
        <button class="primary block" data-act="endGame">🏁 סגירת הערב והתחשבנות</button>
        <div class="row wrap" style="margin-top:10px">
          <button class="sm" data-act="editSettings">עריכת השולחן</button>
          <button class="sm" data-act="resetInvite">קישור הזמנה חדש</button>
          <button class="sm danger" data-act="deleteGame">מחיקה</button></div>`
      : `<div class="row wrap"><button class="sm" data-act="reopen">פתיחה מחדש</button>
          <button class="sm danger" data-act="deleteGame">מחיקת הערב</button></div>`}
    </div>` : '';

  $app.innerHTML = `
    <a class="back" href="#/">‹ בית</a>
    <div class="row between" style="align-items:flex-start;margin-bottom:12px">
      <div class="grow"><h1>${esc(g.name)}</h1>
        <p class="muted small">${esc(fmtDate(g.date))}${g.location ? ' · ' + esc(g.location) : ''} · מארח: ${esc(user(g.adminId).name)} · ${esc(CURRENCY[cur].label)}</p></div>
      ${live ? '<span class="tag pill-live">בשידור חי</span>' : '<span class="tag">סגור</span>'}
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
    <details class="card"><summary>יומן פעילות</summary>
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
    toast(g.isAdmin ? `נוסף ${money(amt, g.currency)}` : 'נשלח לאישור המארח');
  },
  async buyinCustom() {
    const g = state.game;
    const v = await promptDialog('סכום אחר', { label: `סכום ב${CURRENCY[g.currency].label}`, type: 'number', okLabel: g.isAdmin ? 'הוספה' : 'בקשה' });
    if (v == null || v === '') return;
    await gameAction('POST', '/entries', { amount: Number(v) });
  },
  async addFor(el) {
    const g = state.game;
    const name = (g.users[el.dataset.uid] || {}).name;
    const v = await promptDialog(`הוספת כניסה ל${name}`, { label: `סכום ב${CURRENCY[g.currency].label}`, type: 'number', value: g.buyIns[0], okLabel: 'הוספה' });
    if (v == null || v === '') return;
    await gameAction('POST', '/entries', { amount: Number(v), userId: el.dataset.uid });
  },
  approve: (el) => gameAction('POST', `/entries/${el.dataset.id}/approve`),
  approveAll: () => gameAction('POST', '/entries/approve-all'),
  reject: (el) => gameAction('POST', `/entries/${el.dataset.id}/reject`),
  withdraw: (el) => gameAction('DELETE', `/entries/${el.dataset.id}`),
  async editEntry(el) {
    const v = await promptDialog('עריכת כניסה', { label: `סכום ב${CURRENCY[state.game.currency].label}`, type: 'number', value: el.dataset.amt });
    if (v == null || v === '') return;
    await gameAction('PATCH', `/entries/${el.dataset.id}`, { amount: Number(v) });
  },
  async deleteEntry(el) {
    if (await confirmDialog('למחוק את הכניסה?', 'היא תוסר מהשולחן.', 'מחיקה', true)) await gameAction('DELETE', `/entries/${el.dataset.id}`);
  },
  togglePlayer(el) {
    state.openPlayer = state.openPlayer === el.dataset.uid ? null : el.dataset.uid;
    renderGame(state.game);
  },
  async cashout(el) {
    const g = state.game;
    const line = g.lines.find((l) => l.userId === el.dataset.uid);
    const who = el.dataset.uid === state.user.id ? 'שלכם' : `של ${(g.users[el.dataset.uid] || {}).name}`;
    const v = await promptDialog('ספירה סופית', {
      label: `כמה ז׳יטונים ${who}?`, type: 'number', value: line && line.cashChips != null ? line.cashChips : '',
      hint: `ז׳יטון = ${money(g.chipValue, g.currency)}. השאירו ריק כדי לנקות.`,
    });
    if (v == null) return;
    await gameAction('PUT', `/cashouts/${el.dataset.uid}`, { chips: v === '' ? null : Number(v) });
  },
  async removePlayer(el) {
    const name = (state.game.users[el.dataset.uid] || {}).name;
    if (await confirmDialog(`להוציא את ${name}?`, 'גם הכניסות בשולחן הזה יימחקו.', 'הוצאה', true)) {
      state.openPlayer = null;
      await gameAction('DELETE', `/players/${el.dataset.uid}`);
    }
  },
  async makeHost(el) {
    const name = (state.game.users[el.dataset.uid] || {}).name;
    if (await confirmDialog(`להעביר את האירוח ל${name}?`, 'לא תוכלו יותר לנהל את השולחן הזה.', 'העברה')) await gameAction('POST', '/host', { userId: el.dataset.uid });
  },
  async endGame() {
    try { await gameAction('POST', '/end', {}); toast('הערב נסגר. ההתחשבנות למטה.'); }
    catch (e) {
      if (e.data && e.data.code === 'unbalanced') {
        if (await confirmDialog('הז׳יטונים לא מסתדרים', `${e.message}. אפשר לספור שוב, או לסגור בכל זאת והתשלומים יהיו לא מדויקים בסכום הזה.`, 'לסגור בכל זאת', true)) {
          await gameAction('POST', '/end', { force: true });
        }
      } else throw e;
    }
  },
  reopen: () => gameAction('POST', '/reopen'),
  paid: (el) => gameAction('POST', `/settlements/${el.dataset.idx}`, { paid: el.dataset.paid === '1' }),
  async deleteGame() {
    if (await confirmDialog('למחוק את הערב?', 'כל הכניסות והתוצאות יימחקו לכולם. אי אפשר לבטל.', 'מחיקה', true)) {
      await api('DELETE', `/api/games/${state.game.id}`);
      location.hash = '#/';
    }
  },
  async resetInvite() {
    if (await confirmDialog('ליצור קישור הזמנה חדש?', 'הקישור הישן יפסיק לעבוד. מי שכבר בשולחן נשאר.', 'קישור חדש')) await gameAction('POST', '/invite/reset');
  },
  copyInvite: () => copyText(inviteLink(state.game)),
  shareInvite: () => navigator.share({ title: state.game.name, text: `הצטרפו ל${state.game.name}`, url: inviteLink(state.game) }).catch(() => {}),
  copyStandings: () => copyText(standingsText(state.game)),
  editSettings: () => editSettings(),
};

async function editSettings() {
  const g = state.game;
  $dialog.innerHTML = `<form method="dialog" id="settings"><h2>עריכת השולחן</h2>
    <div class="field"><label>שם הערב</label><input name="name" value="${esc(g.name)}" maxlength="40"></div>
    <div class="row"><div class="field grow"><label>תאריך</label><input type="date" name="date" value="${esc(g.date)}"></div>
    <div class="field grow"><label>איפה</label><input name="location" value="${esc(g.location || '')}" maxlength="60"></div></div>
    <div class="row"><div class="field grow"><label>מטבע</label><select name="currency">${Object.entries(CURRENCY).map(([k, v]) => `<option value="${k}" ${k === g.currency ? 'selected' : ''}>${v.symbol} ${v.label}</option>`).join('')}</select></div>
    <div class="field grow"><label>ז׳יטון אחד =</label><input name="chipValue" type="number" step="any" inputmode="decimal" value="${g.chipValue}"></div></div>
    <div class="field"><label>סכומי כניסה (מופרדים בפסיק)</label><input name="buyIns" value="${esc(g.buyIns.join(', '))}" inputmode="decimal"></div>
    <label class="row small" style="gap:8px"><input type="checkbox" name="allowCustom" style="width:auto;min-height:0" ${g.allowCustom ? 'checked' : ''}> שחקנים יכולים לבקש גם סכום אחר</label>
    <div class="row" style="justify-content:flex-end;margin-top:14px"><button value="cancel" class="ghost">ביטול</button><button value="ok" class="primary">שמירה</button></div></form>`;
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
      toast('נשמר');
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
    $app.innerHTML = `<h1>סטטיסטיקה</h1><div class="card"><p>עדיין אין ערבים סגורים.</p>
      <p class="muted small">ברגע שמארח סוגר ערב, התוצאות של כולם יופיעו כאן: רווח, אחוז ניצחונות, רצפים ועוד.</p></div>`;
    return;
  }
  const rows = data.players.filter((p) => p.byCurrency[cur]).map((p) => ({ ...p, s: p.byCurrency[cur] }))
    .sort((a, b) => b.s.net - a.s.net);
  const top = (fn, min = 1) => rows.filter((r) => r.s.games >= min).sort((a, b) => fn(b) - fn(a))[0];
  const fame = [
    ['💰', 'הרווח הגדול', top((r) => r.s.net), (r) => signed(r.s.net, cur)],
    ['🚀', 'הערב הכי טוב', top((r) => r.s.best), (r) => signed(r.s.best, cur)],
    ['🎯', `אחוז ניצחונות הכי גבוה (${ltr('3+')} ערבים)`, top((r) => r.s.winRate, 3), (r) => pct(r.s.winRate)],
    ['🔥', 'הרצף הכי חם עכשיו', top((r) => r.s.streak), (r) => (r.s.streak >= 2 ? `${r.s.streak} ניצחונות ברצף` : null)],
    ['🪑', 'הכי הרבה ערבים', top((r) => r.s.games), (r) => `${r.s.games}`],
    ['🎁', 'הכי נדיבים לקופה', top((r) => -r.s.net), (r) => (r.s.net < 0 ? signed(r.s.net, cur) : null)],
  ].filter(([, , r, f]) => r && f(r));
  $app.innerHTML = `
    <h1>סטטיסטיקה</h1>
    <p class="muted small">כל מי שישבתם איתו. רק ערבים סגורים.</p>
    ${data.currencies.length > 1 ? `<div class="seg" style="margin-bottom:14px">${data.currencies.map((c) => `<button data-cur="${c}" class="${c === cur ? 'on' : ''}">${sym(c)} ${CURRENCY[c].label}</button>`).join('')}</div>` : ''}
    <div class="card"><h3>טבלת המובילים</h3>
      <table class="lb"><thead><tr><th>#</th><th>שחקן</th><th class="r">ערבים</th><th class="r">ניצחונות</th><th class="r">רווח</th></tr></thead>
      <tbody>${rows.map((r, i) => `<tr data-href="#/player/${r.user.id}">
        <td class="muted">${i + 1}</td>
        <td><div class="row" style="gap:8px">${avatar(r.user)}<div><b>${esc(r.user.name)}</b>${r.user.id === state.user.id ? ' <span class="small muted">(אתם)</span>' : ''}
          <div class="small muted">${r.badges.map((b) => b.icon).join(' ')} ממוצע ${signed(r.s.avg, cur)}</div></div></div></td>
        <td class="r num">${r.s.games}</td><td class="r num">${pct(r.s.winRate)}</td>
        <td class="r num"><b class="${netClass(r.s.net)}">${signed(r.s.net, cur)}</b></td></tr>`).join('')}</tbody></table></div>
    <div class="card"><h3>היכל התהילה</h3><ul class="list">${fame.map(([icon, label, r, f]) => `<li class="row">
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
    <a class="back" href="#/stats">‹ סטטיסטיקה</a>
    <div class="hero-head">${avatar(data.user, 'lg')}<div><h1 style="margin:0">${esc(data.user.name)}</h1>
      <div class="row wrap" style="gap:6px;margin-top:4px">${data.badges.map((b) => `<span class="tag" title="${esc(b.hint)}">${b.icon} ${esc(b.label)}</span>`).join('')}</div></div></div>
    ${!s ? `<div class="card"><p class="muted">עדיין אין ערבים סגורים.</p></div>` : `
    ${curs.length > 1 ? `<div class="seg" style="margin-bottom:14px">${curs.map((c) => `<button data-cur="${c}" class="${c === cur ? 'on' : ''}">${sym(c)} ${CURRENCY[c].label}</button>`).join('')}</div>` : ''}
    <div class="card">
      <div class="tiles">
        <div class="tile"><div class="v ${netClass(s.net)}">${signed(s.net, cur)}</div><div class="k">רווח כולל</div></div>
        <div class="tile"><div class="v">${s.games}</div><div class="k">ערבים</div></div>
        <div class="tile"><div class="v">${pct(s.winRate)}</div><div class="k">ערבים ברווח</div></div>
        <div class="tile"><div class="v ${netClass(s.avg)}">${signed(s.avg, cur)}</div><div class="k">ממוצע לערב</div></div>
        <div class="tile"><div class="v ${netClass(s.roi)}">${ltr(`${s.roi > 0 ? '+' : ''}${Math.round(s.roi * 100)}%`)}</div><div class="k">תשואה על הכניסות</div></div>
        <div class="tile"><div class="v">${s.streak > 0 ? `🔥 ${s.streak} נצ׳` : s.streak < 0 ? `🧊 ${-s.streak} הפ׳` : '–'}</div><div class="k">רצף נוכחי</div></div>
        <div class="tile"><div class="v ${netClass(s.best)}">${signed(s.best, cur)}</div><div class="k">הערב הכי טוב</div></div>
        <div class="tile"><div class="v ${netClass(s.worst)}">${signed(s.worst, cur)}</div><div class="k">הערב הכי גרוע</div></div>
        <div class="tile"><div class="v">${money(s.totalBuyIn, cur)}</div><div class="k">סך הכניסות</div></div>
      </div>
    </div>
    <div class="card"><h3>רווח לאורך זמן</h3>${profitChart(s.results, cur)}</div>
    <div class="card"><h3>ערבים</h3><ul class="list">${s.results.slice().reverse().map((r) => `<li><a class="item" href="#/game/${r.gameId}">
      <div class="grow"><b>${esc(r.name)}</b><div class="small muted">${esc(fmtDate(r.date))} · ${r.players} שחקנים · כניסה ${money(r.buyIn, cur)}</div></div>
      <b class="num ${netClass(r.net)}">${signed(r.net, cur)}</b></a></li>`).join('')}</ul></div>`}`;
  $app.querySelectorAll('[data-cur]').forEach((b) => b.addEventListener('click', () => { store.set('pn.statsCur', b.dataset.cur); viewPlayer(uid); }));
  wireChart();
}

// Cumulative profit line. One series, so no legend: the card title names it.
function profitChart(results, cur) {
  if (results.length < 2) return '<p class="small muted">עוד כמה ערבים והמגמה תופיע כאן.</p>';
  const W = 520, H = 200, P = { l: 8, r: 8, t: 14, b: 22 };
  let run = 0;
  const pts = [{ v: 0, label: 'התחלה' }].concat(results.map((r) => { run += r.net; return { v: Math.round(run * 100) / 100, label: `${fmtDate(r.date)} · ${r.name}`, net: r.net }; }));
  const min = Math.min(0, ...pts.map((p) => p.v)), max = Math.max(0, ...pts.map((p) => p.v));
  const span = max - min || 1;
  const x = (i) => P.l + (i * (W - P.l - P.r)) / (pts.length - 1);
  const y = (v) => P.t + ((max - v) * (H - P.t - P.b)) / span;
  const d = pts.map((p, i) => `${i ? 'L' : 'M'}${x(i).toFixed(1)},${y(p.v).toFixed(1)}`).join('');
  const last = pts[pts.length - 1];
  const color = last.v >= 0 ? 'var(--win)' : 'var(--lose)';
  const data = pts.map((p, i) => ({ x: x(i) / W, y: y(p.v) / H, text: `${p.label}${p.net != null ? ` · ${signed(p.net, cur)}` : ''} · מצטבר ${signed(p.v, cur)}` }));
  return `<div class="chart" data-points='${esc(JSON.stringify(data))}'>
    <svg viewBox="0 0 ${W} ${H}" role="img" aria-label="רווח מצטבר, כרגע ${esc(signed(last.v, cur))}">
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
    <a class="back" href="#/">‹ בית</a>
    <div class="hero-head">${avatar(u, 'lg')}<h1 style="margin:0">החשבון שלי</h1></div>
    <form class="card" id="nameForm"><div class="field"><label>שם</label><input name="name" value="${esc(u.name)}" maxlength="24"></div>
      <label>צבע</label><div class="row wrap" style="margin-bottom:14px">${COLORS.map((c) => `<button type="button" data-color="${c}" aria-label="צבע" style="width:36px;height:36px;min-height:0;padding:0;border-radius:50%;background:${c};${c === u.color ? 'outline:3px solid var(--gold)' : ''}"></button>`).join('')}</div>
      <button class="primary">שמירה</button></form>
    <form class="card" id="pinForm"><h3>שינוי קוד</h3>
      <div class="row"><div class="field grow"><label>קוד נוכחי</label><input name="currentPin" class="pin" type="password" inputmode="numeric" maxlength="6" autocomplete="current-password"></div>
      <div class="field grow"><label>קוד חדש</label><input name="pin" class="pin" type="password" inputmode="numeric" maxlength="6" autocomplete="new-password"></div></div>
      <button>עדכון קוד</button></form>
    <div class="card"><h3>התקנה בטלפון</h3><p class="small muted">באייפון: שיתוף ← הוספה למסך הבית. באנדרואיד: תפריט ← התקנת האפליקציה. מאז היא נפתחת כמו כל אפליקציה.</p></div>
    <button class="danger block" id="logout">התנתקות</button>`;
  let color = u.color;
  $app.querySelectorAll('[data-color]').forEach((b) => b.addEventListener('click', () => {
    color = b.dataset.color;
    $app.querySelectorAll('[data-color]').forEach((x) => { x.style.outline = x === b ? '3px solid var(--gold)' : ''; });
  }));
  document.getElementById('nameForm').addEventListener('submit', async (e) => {
    e.preventDefault();
    try {
      const r = await api('PATCH', '/api/me', { name: e.target.name.value, color });
      state.user = r.user; store.set('pn.user', r.user); store.set('pn.lastName', r.user.name); toast('נשמר'); viewAccount();
    } catch (err) { toast(err.message, true); }
  });
  document.getElementById('pinForm').addEventListener('submit', async (e) => {
    e.preventDefault();
    try { await api('PATCH', '/api/me', { currentPin: e.target.currentPin.value, pin: e.target.pin.value }); e.target.reset(); toast('הקוד עודכן'); }
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
      ${arr.length ? `<button class="sm ghost" data-clear="${key}">ניקוי</button>` : ''}</div><div class="slots" style="margin-bottom:12px">${cells.join('')}</div>`;
  };
  const deck = [];
  for (const s of [0, 1, 2, 3]) for (let r = 12; r >= 0; r--) {
    const c = r * 4 + s;
    const suit = PH.SUITS[s];
    deck.push(`<button data-card="${c}" class="${suit === 'h' || suit === 'd' ? 'red' : ''}" ${used.has(c) ? 'disabled' : ''}>${PH.RANKS[r] === 'T' ? '10' : PH.RANKS[r]}<span>${PH.SUIT_SYMBOL[suit]}</span></button>`);
  }

  $app.innerHTML = `
    <h1>בודק ידיים</h1>
    <p class="muted small">בחרו את שני הקלפים שלכם, ואחר כך את הקלפים על השולחן. אפשר להוסיף את היד של יריב כדי לסגור ויכוחים של "מי היה מוביל?".</p>
    <div class="card">
      ${slotRow('hero', 'היד שלכם')}
      ${slotRow('board', 'השולחן (פלופ · טרן · ריבר)')}
      ${slotRow('villain', 'היד של היריב (לא חובה)')}
      <div class="row between"><span class="small">שחקנים נגדכם</span>
        <div class="row" style="gap:6px"><button class="sm" data-opp="-1">−</button><b class="num" style="min-width:20px;text-align:center">${hands.opponents}</b><button class="sm" data-opp="1">＋</button></div></div>
    </div>
    <div class="card"><div class="deck">${deck.join('')}</div>
      <div class="row" style="margin-top:10px"><button class="sm ghost grow" data-reset>איפוס הכול</button></div></div>
    <div id="handResult"></div>
    <details class="card"><summary>דירוג הידיים</summary>
      <ol style="margin:10px 0 0;padding-inline-start:22px;line-height:1.8">
        ${PH.CATEGORIES.slice().reverse().map((c, i) => `<li><b>${c === 'סטרייט פלאש' ? 'סטרייט פלאש (רויאל = עד אס)' : c}</b> <span class="small muted">${['<bdi dir="ltr">A♠ K♠ Q♠ J♠ 10♠</bdi>', '<bdi dir="ltr">9♣ 9♦ 9♥ 9♠</bdi>', '<bdi dir="ltr">K K K 7 7</bdi>', '5 קלפים מאותה צורה', '5 ברצף', '<bdi dir="ltr">Q Q Q</bdi>', '<bdi dir="ltr">J J 4 4</bdi>', '<bdi dir="ltr">A A</bdi>', 'כלום: הקלף הכי גבוה'][i]}</span></li>`).join('')}
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
  if (hero.length < 2) { out.innerHTML = '<div class="card"><p class="muted">בחרו שני קלפים כדי לראות כמה הם חזקים.</p></div>'; return; }
  if (board.length === 1 || board.length === 2) { out.innerHTML = '<div class="card"><p class="muted">בפלופ יש שלושה קלפים: הוסיפו עוד אחד או שניים.</p></div>'; return; }
  const pre = PH.preflopTier(hero);
  const made = board.length ? PH.describe(PH.evaluate(hero.concat(board))) : null;
  const villains = villain.length === 2 ? [villain] : [];
  const street = ['פרה־פלופ', , , 'פלופ', 'טרן', 'ריבר'][board.length];
  out.innerHTML = `<div class="card"><p class="muted">מחשב סיכויים ב${street}…</p></div>`;
  setTimeout(() => {
    const eq = PH.equity({ hero, board, villains, opponents: Math.max(hands.opponents, villains.length), iterations: board.length === 5 ? 2000 : 6000 });
    const outs = PH.outs(hero, board);
    const vMade = villains.length && board.length ? PH.describe(PH.evaluate(villain.concat(board))) : null;
    const w = eq.win * 100, t = eq.tie * 100, l = eq.lose * 100;
    const label = eq.equity >= 0.65 ? ['💪', 'פייבוריט ברור'] : eq.equity >= 0.5 ? ['👍', 'יתרון קל'] : eq.equity >= 0.3 ? ['🤔', 'מאחור, אבל עוד בחיים'] : ['🥶', 'אנדרדוג גדול'];
    out.innerHTML = `<div class="card">
      <div class="row between"><h3>${street}</h3><span class="small muted">מול ${Math.max(hands.opponents, villains.length) > 1 ? `${Math.max(hands.opponents, villains.length)} שחקנים` : 'שחקן אחד'}</span></div>
      ${made ? `<h2>${esc(made)}</h2>` : `<h2><bdi dir="ltr">${PH.handLabel(hero)}</bdi> · ${pre.tier}</h2><p class="small muted">ציון צ׳ן ${ltr(`${pre.chen}/20`)} · ${esc(pre.note)}</p>`}
      ${vMade ? `<p class="small">ליריב יש <b>${esc(vMade)}</b></p>` : ''}
      <p style="margin-top:10px"><span style="font-size:28px;font-weight:800" class="num">${pct(eq.equity)}</span> <span class="muted">לזכות בקופה</span> · ${label[0]} ${label[1]}</p>
      <div class="bar" role="img" aria-label="ניצחון ${pct(eq.win)}, תיקו ${pct(eq.tie)}, הפסד ${pct(eq.lose)}">
        <div class="w" style="width:${w}%">${w >= 12 ? 'ניצחון ' + pct(eq.win) : ''}</div>
        ${t >= 0.5 ? `<div class="t" style="width:${t}%">${t >= 12 ? 'תיקו ' + pct(eq.tie) : ''}</div>` : ''}
        <div class="l" style="width:${l}%">${l >= 12 ? 'הפסד ' + pct(eq.lose) : ''}</div></div>
      <p class="small muted" style="margin-top:6px">ניצחון ${pct(eq.win)} · תיקו ${pct(eq.tie)} · הפסד ${pct(eq.lose)}${villains.length ? ` · הסיכוי של היריב ${pct(eq.villainEquity[0])}` : ''}</p>
      ${outs.length ? `<p class="small" style="margin-top:10px"><b>${outs.length} אאוטים</b> לשיפור: <bdi dir="ltr">${outs.map((c) => PH.RANKS[PH.rankOf(c)] + PH.SUIT_SYMBOL[PH.SUITS[PH.suitOf(c)]]).join(' ')}</bdi>
        <span class="muted">(≈${pct(Math.min(100, outs.length * (board.length === 3 ? 4 : 2)) / 100)} עד הריבר, חוק ה־${board.length === 3 ? '4' : '2'})</span></p>` : ''}
      ${board.length < 5 ? `<h3 style="margin-top:14px">לאן היד שלכם תגיע</h3>
        <div class="dist">${eq.categories.map((p, i) => ({ p, i })).filter((x) => x.p >= 0.005).reverse().map(({ p, i }) => `
          <span>${PH.CATEGORIES[i]}</span><div class="track"><div class="fill" style="width:${(p * 100).toFixed(1)}%"></div></div><span class="num" style="text-align:end">${pct(p)}</span>`).join('')}</div>` : ''}
      <p class="small muted" style="margin-top:10px">לפי ${eq.iterations.toLocaleString('he-IL')} הדמיות אקראיות.</p>
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
    <h1>שעון בליינדים</h1>
    <div class="card center">
      <p class="muted">שלב ${timer.level + 1} מתוך ${timer.levels.length}</p>
      <div class="timer-blinds num" dir="ltr">${lv[0]} / ${lv[1]}</div>
      <div class="timer-clock" id="clock" dir="ltr"></div>
      <p class="small muted">${next ? `הבא: ${ltr(`${next[0]} / ${next[1]}`)}` : 'השלב האחרון'}</p>
      <div class="row" style="margin-top:12px">
        <button data-t="prev" aria-label="השלב הקודם">⏭</button>
        <button class="primary grow" data-t="toggle" style="min-height:56px;font-size:18px">${timer.running ? 'עצירה' : 'התחלה'}</button>
        <button data-t="next" aria-label="השלב הבא">⏮</button></div>
    </div>
    <div class="card">
      <div class="row between"><span>דקות לכל שלב</span>
        <div class="row" style="gap:6px"><button class="sm" data-t="minus">−</button><b class="num" style="min-width:28px;text-align:center">${timer.minutes}</b><button class="sm" data-t="plus">＋</button></div></div>
      <details style="margin-top:12px"><summary>שלבי הבליינדים</summary>
        <div class="field" style="margin-top:8px"><label>שלב בכל שורה: קטן/גדול</label>
        <textarea id="levels" rows="8" dir="ltr">${timer.levels.map((l) => l.join('/')).join('\n')}</textarea></div>
        <div class="row"><button class="sm" data-t="saveLevels">שמירת השלבים</button><button class="sm ghost" data-t="defaults">ברירת מחדל</button></div></details>
      <p class="small muted" style="margin-top:10px">המסך נשאר דולק בזמן שהשעון רץ, ויש צפצוף כשהבליינדים עולים.</p>
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
      if (!parsed.length) return toast('הוסיפו לפחות שלב אחד, למשל 5/10', true);
      timer.levels = parsed; timer.level = Math.min(timer.level, parsed.length - 1); saveTimer(); toast('השלבים נשמרו');
    }
    viewTimer();
  }));
}

// ---------------------------------------------------------------- boot
window.PN = { state, store, router };
router();
