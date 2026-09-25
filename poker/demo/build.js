'use strict';
// Builds a single self-contained HTML demo: the app plus lib/api.js running in the browser.
// Usage: node demo/build.js [out.html]
const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..');
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8');
const out = process.argv[2] || path.join(__dirname, 'poker-night-demo.html');
const mod = (name, file) => `PN_DEFINE(${JSON.stringify(name)}, function (module, exports, require, __dirname) {\n${read(file)}\n});`;
const script = (code) => `<script>\n${code.replace(/<\/script/gi, '<\\/script')}\n</script>`;

const html = `<title>ערב פוקר</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Rubik:wght@400;500;700;800&display=swap">
<meta name="theme-color" content="#0f2a1f">
<style>
${read('public/style.css')}
#app { padding-top: 12px; }
#demoBar {
  max-width: 560px; margin: 0 auto; padding: 10px 16px 0;
  display: flex; flex-wrap: wrap; align-items: center; gap: 8px;
  font-size: 13px; color: var(--ink-2);
}
#demoBar .tag { background: var(--gold); color: var(--gold-ink); border-color: var(--gold); font-weight: 700; }
#demoBar select { width: auto; min-height: 34px; padding: 4px 10px; font-size: 14px; }
#demoBar button { margin-inline-start: auto; }
</style>
<div id="demoBar" dir="rtl" lang="he">
  <span class="tag">הדגמה</span>
  <label for="demoWho" style="margin:0">משחקים בתור</label>
  <select id="demoWho"></select>
  <button class="sm ghost" id="demoReset">איפוס</button>
  <p class="small muted" style="width:100%;margin:0">קבוצה לדוגמה, שמורה רק בטלפון הזה. החליפו שחקן כדי לראות את הצד של חבר.</p>
</div>
<div dir="rtl" lang="he">
${read('public/index.html').match(/<main[\s\S]*<dialog id="dialog"><\/dialog>/)[0]}
</div>
${script(read('public/hand.js'))}
${script(read('demo/shim.js') + '\n' + mod('./logic', 'lib/logic.js') + '\n' + mod('./api', 'lib/api.js') + '\nPN_BOOT_DEMO();')}
${script(read('public/app.js'))}
${script(read('demo/bar.js'))}
`;
fs.writeFileSync(out, html);
console.log(`Wrote ${out} (${(html.length / 1024).toFixed(0)} KB)`);
