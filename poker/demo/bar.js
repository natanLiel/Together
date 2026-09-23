// Demo bar: switch between players to see the host's and a player's side.
(function () {
  'use strict';
  const bar = document.getElementById('demoBar');
  const sel = bar.querySelector('select');
  const { data, newSession, KEY } = window.PN_DEMO;
  function fill() {
    const current = window.PN.state.user && window.PN.state.user.id;
    sel.innerHTML = Object.values(data.users).map((u) => `<option value="${u.id}" ${u.id === current ? 'selected' : ''}>${u.name.replace(/[<>&"]/g, '')}</option>`).join('');
  }
  sel.addEventListener('focus', fill);
  sel.addEventListener('change', () => {
    const s = newSession(sel.value);
    const { state, store, router } = window.PN;
    state.token = s.token; state.user = s.user; state.me = null; state.openPlayer = null;
    store.set('pn.token', s.token); store.set('pn.user', s.user);
    if (/^#\/(login|join)/.test(location.hash)) location.hash = '#/'; else router();
  });
  bar.querySelector('#demoReset').addEventListener('click', () => {
    try { for (const k of Object.keys(localStorage)) if (k.startsWith('pn.')) localStorage.removeItem(k); } catch { /* storage blocked */ }
    try { localStorage.removeItem(KEY); } catch { /* storage blocked */ }
    location.hash = '#/';
    location.reload();
  });
  window.addEventListener('hashchange', fill);
  fill();
  setInterval(fill, 2000);
})();
