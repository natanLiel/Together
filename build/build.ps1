$ErrorActionPreference = "Stop"
$scratch = Join-Path $PSScriptRoot "parts"
$repoDir = Split-Path $PSScriptRoot -Parent
$utf8    = New-Object System.Text.UTF8Encoding($false)

$src   = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot "source\Together.dc.html"), [System.Text.Encoding]::UTF8)
$bundl = [System.IO.File]::ReadAllText("$scratch\app-template.dc.html", [System.Text.Encoding]::UTF8)  # pristine bundled export
$style = [System.IO.File]::ReadAllText("$scratch\newstyle.css.html", [System.Text.Encoding]::UTF8)

# ── 1. take the bundled preamble (inlined Organic CSS, @font-face, _ds bundle) ──
$hOpen = $bundl.IndexOf("<helmet>"); if ($hOpen -lt 0) { throw "no <helmet> in bundled export" }
$hClose = $bundl.IndexOf("</helmet>"); if ($hClose -lt 0) { throw "no </helmet> in bundled export" }
$lastStyle = $bundl.LastIndexOf("<style>", $hClose)
if ($lastStyle -lt $hOpen) { throw "could not locate the override <style> in bundled export" }
$preamble = $bundl.Substring($hOpen + 8, $lastStyle - ($hOpen + 8))
if ($preamble -notmatch 'Caprasimo' -or $preamble -notmatch '110ecd0d') { throw "preamble missing Organic CSS or the _ds bundle" }

# ── 2. take their head (up to <helmet>) and their body (from </helmet>) ──
$sHOpen = $src.IndexOf("<helmet>"); if ($sHOpen -lt 0) { throw "no <helmet> in your source" }
$sHClose = $src.IndexOf("</helmet>"); if ($sHClose -lt 0) { throw "no </helmet> in your source" }
$head = $src.Substring(0, $sHOpen)
$rest = $src.Substring($sHClose)          # "</helmet> ... markup ... script ... </x-dc></body></html>"

$doc = $head + "<helmet>" + $preamble + $style.TrimEnd() + "`n" + $rest

# ── 3. encode camelCase attributes the way the bundler does ──
$camel = 'dangerouslySetInnerHTML','onBlur','onChange','onClick','onFocus','onInput','onKeyDown',
         'onPointerCancel','onPointerDown','onPointerMove','onPointerUp','onScroll','viewBox'
foreach ($a in $camel) {
    $kebab = [regex]::Replace($a, '([A-Z])', { param($m) '-' + $m.Groups[1].Value.ToLower() })
    $doc = [regex]::Replace($doc, "(\s)$a=", "`${1}sc-camel-$kebab=")
}
if ($doc -match '\s(onClick|viewBox|dangerouslySetInnerHTML)=') { throw "camelCase attributes survived the transform" }

# ── 4. point asset references at the bundle's embedded copies ──
$assets = @{
    './support.js'                                            = '46750274-63fa-47e7-91bc-03bfe95c1972'
    '_ds/organic-0cc667cc-78e5-4a6f-b79f-a438fc482d45/_ds_bundle.js' = '110ecd0d-18f8-4452-9038-22f9ef1381db'
    'assets/logo-dark.svg'                                    = '50724986-eeed-4c4e-80f2-0381989e91fb'
    'assets/logo-light.svg'                                   = '87514453-9a7a-41a6-a2f3-e56ebc12c57f'
    'assets/mark.svg'                                         = '2e1211b0-91e5-44d2-a0a0-5f552f929418'
}
foreach ($k in $assets.Keys) { $doc = $doc.Replace('"' + $k + '"', '"' + $assets[$k] + '"') }
if ($doc -match 'src="assets/(mark|logo-dark|logo-light)\.svg"') { throw "asset paths survived the mapping" }

# ── 5. the splash mark gradient -> the two inks ──
$doc = $doc.Replace('<stop offset="0" stop-color="#F0A8C2"/><stop offset="1" stop-color="#B07AC8"/>',
                    '<stop offset="0" stop-color="#2A3F6E"/><stop offset="1" stop-color="#E4485B"/>')
$doc = $doc.Replace('<stop offset="0" stop-color="#F0A8C2"></stop><stop offset="1" stop-color="#B07AC8"></stop>',
                    '<stop offset="0" stop-color="#2A3F6E"></stop><stop offset="1" stop-color="#E4485B"></stop>')

# ── 5b. carry the inline dark-theme colours over to Two Inks ──────────────────
#  The newer source hardcodes literal whites inline (the old export used tokens),
#  which are invisible on a stock ground. Mapped per-tag so that text sitting on
#  top of a photograph stays light while everything else becomes ink.
$opts = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
$evaluator = {
    param($m)
    $tag = $m.Value
    $onImage = [regex]::IsMatch($tag, 'url\(assets/people/', $opts)
    $fg = if ($onImage) { '#E3E1D8' } else { '#1C2536' }
    $tag = [regex]::Replace($tag, 'color:\s*#(fff|ffffff)\b', "color:$fg", $opts)
    $tag = [regex]::Replace($tag, 'stroke="#(fff|ffffff)"', "stroke=`"$fg`"", $opts)
    $tag = [regex]::Replace($tag, 'fill="#(fff|ffffff)"', "fill=`"$fg`"", $opts)
    $tag = [regex]::Replace($tag, 'rgba\(255,\s*255,\s*255', 'rgba(28,37,54', $opts)
    return $tag
}
$doc = [regex]::Replace($doc, '<[^>]*>', $evaluator)
$leftWhite = ([regex]::Matches($doc, 'rgba\(255,\s*255,\s*255|color:\s*#f{3,6}\b', $opts)).Count
Write-Output ("inline whites remaining after mapping: {0}" -f $leftWhite)

# ── 5c. route inline fonts through the type tokens ────────────────────────────
#  Only below </helmet>: the @font-face blocks above it declare the very same
#  family names, and rewriting those would unregister the embedded faces.
$cut = $doc.IndexOf("</helmet>"); if ($cut -lt 0) { throw "no </helmet> when mapping fonts" }
$top = $doc.Substring(0, $cut)
$bot = $doc.Substring($cut)
$fontMap = @{
    "font-family:\s*'Instrument Serif'[^;`"]*" = 'font-family:var(--font-heading)'
    "font-family:\s*'Instrument Sans'[^;`"]*"  = 'font-family:var(--font-body)'
    "font-family:\s*'Archivo'[^;`"]*"          = 'font-family:var(--font-meta)'
}
foreach ($k in $fontMap.Keys) { $bot = [regex]::Replace($bot, $k, $fontMap[$k]) }
$doc = $top + $bot
$leftFonts = ([regex]::Matches($bot, "font-family:\s*'(Instrument Serif|Instrument Sans|Archivo)'")).Count
Write-Output ("inline hardcoded fonts remaining in markup: {0}" -f $leftFonts)

# ── 5d. map the plum-black palette to Two Inks, in markup AND in the logic ────
#  Selected states, chip colours and the primary gradient are computed in
#  JavaScript, so they sit in string literals the tag pass above cannot see.
#  Everything here is below </helmet>, so the design tokens stay untouched.
$cut2 = $doc.IndexOf("</helmet>")
$top2 = $doc.Substring(0, $cut2)
$bot2 = $doc.Substring($cut2)
$palette = [ordered]@{
    'linear-gradient(150deg,#F0A8C2,#E0759A 52%,#B07AC8)' = 'linear-gradient(150deg,#E4485B,#E4485B)'
    '#F7CBDB' = '#1C2536'   # selected chip / tab label -> ink
    '#F0A8C2' = '#EBB6BE'   # light rose tint
    '#E0759A' = '#E4485B'   # rose  -> ink two
    '#B07AC8' = '#57304F'   # plum  -> the overprint
    '#1A0E16' = '#1C2536'   # ink used on rose fills
    '#14101A' = '#E3E1D8'   # the old ground -> stock
    '#0B0910' = '#1C2536'
}
foreach ($k in $palette.Keys) { $bot2 = $bot2.Replace($k, $palette[$k]) }
$bot2 = [regex]::Replace($bot2, 'rgba\(255,\s*255,\s*255', 'rgba(28,37,54')
$bot2 = [regex]::Replace($bot2, "'#FFFFFF'", "'#1C2536'", $opts)
$doc = $top2 + $bot2
$leftLegacy = ([regex]::Matches($bot2, '#(F7CBDB|E0759A|B07AC8|1A0E16|14101A)|rgba\(255,\s*255,\s*255', $opts)).Count
Write-Output ("legacy palette values remaining below helmet: {0}" -f $leftLegacy)

# ── 5e. the same palette again, in rgb() triplet form ─────────────────────────
#  Inline styles spell the old colours as rgba(224,117,154,.65) rather than in
#  hex, so the hex pass above walked straight past them. This is what left
#  near-black fills and rose glows on the action buttons.
$cut3 = $doc.IndexOf("</helmet>")
$top3 = $doc.Substring(0, $cut3); $bot3 = $doc.Substring($cut3)
$triplets = [ordered]@{
    '224,\s*117,\s*154' = '228,72,91'    # rose      -> ink two
    '240,\s*168,\s*194' = '235,182,190'  # light rose
    '176,\s*122,\s*200' = '87,48,79'     # plum      -> overprint
    '20,\s*16,\s*26'    = '227,225,216'  # the old ground -> stock
    '26,\s*14,\s*22'    = '28,37,54'     # ink on rose
    '11,\s*9,\s*16'     = '28,37,54'
}
foreach ($k in $triplets.Keys) { $bot3 = [regex]::Replace($bot3, $k, $triplets[$k]) }

# ── 5f. square off the full-width action buttons and drop the embossing ───────
#  These carry inline radii and inset/glow shadows from the dark build, and
#  inline styles beat the stylesheet. Only full-width buttons are touched, so
#  genuinely circular controls (the ring, like and pass) keep their shape.
$btnEval = {
    param($m)
    $tag = $m.Value
    if ($tag -notmatch 'width:\s*100%' -and $tag -notmatch 'btn-block') { return $tag }
    $tag = $tag -replace 'border-radius:\s*999px', 'border-radius:2px'
    $tag = $tag -replace 'box-shadow:[^;"]*;?', ''
    $tag = $tag -replace 'background-image:\s*linear-gradient\([^)]*\)', 'background:#E4485B'
    return $tag
}
$bot3 = [regex]::Replace($bot3, '<button[^>]*>', $btnEval)

#  Soft 12-32px corners belong to the old system; everything lands on 3px.
#  999px is left alone (circles), and so are 45/56px — that is the phone frame.
$bot3 = [regex]::Replace($bot3,
    '(border(?:-start-(?:start|end))?-radius):\s*(?:12|14|18|20|22|24|26|28|32)px', '$1:3px')
$doc = $top3 + $bot3
$sq = ([regex]::Matches($bot3, '<button[^>]*(width:\s*100%|btn-block)[^>]*border-radius:2px')).Count
Write-Output ("full-width buttons squared: {0} | embossed shadows left: {1}" -f $sq, ([regex]::Matches($bot3,'box-shadow:\s*inset')).Count)

# ── 5g. "Do this later" is a tertiary action, so it loses its outline ─────────
#  An outlined box competes with "Take a selfie"; as plain text the primary
#  action carries the screen on its own.
$doc = [regex]::Replace($doc,
    '<button[^>]*?(sc-camel-on-click="\{\{[^"]*\}\}")[^>]*>\s*Do this later\s*</button>',
    '<button class="btn btn-ghost btn-block tg-tap" style="height:48px;width:100%;font-size:15px" $1>Do this later</button>')
if ($doc -notmatch 'btn-ghost btn-block tg-tap" style="height:48px') { throw "'Do this later' was not restyled" }

# ── 5h. the verify badge, on-system ───────────────────────────────────────────
#  It was a 170px plum circle: plum is reserved for connection, and circles for
#  rings. It becomes a squared tint plate with the shield drawn in ink one.
$doc = [regex]::Replace($doc,
    '<div style="width:170px;height:170px;border-radius:999px;background:var\(--color-accent-2-200\);display:grid;place-items:center">',
    '<div style="width:150px;height:150px;border-radius:3px;background:var(--color-neutral-200);border:1px solid var(--color-divider);display:grid;place-items:center">')
if ($doc -notmatch 'width:150px;height:150px;border-radius:3px') { throw "verify badge not restyled" }
$doc = $doc.Replace('stroke="var(--color-accent-2-700)" stroke-width="2.75"', 'stroke="var(--tg-ink-b)" stroke-width="2"')

# ── 5i. the roster, and a deck that lays each profile out differently ─────────
$roster = [System.IO.File]::ReadAllText("$scratch\roster.js.txt", [System.Text.Encoding]::UTF8)
$startTok = '  static PEOPLE = ['
$endTok   = "static PEOPLE_AWAITING_PHOTOS = ["
$s = $doc.IndexOf($startTok)
$e = $doc.IndexOf($endTok)
if ($s -lt 0 -or $e -lt $s) { throw "could not locate the PEOPLE block" }
$e2 = $doc.IndexOf('];', $e); if ($e2 -lt 0) { throw "unterminated PEOPLE_AWAITING_PHOTOS" }
$doc = $doc.Substring(0, $s) + $roster.TrimEnd() + $doc.Substring($e2 + 2)

#  The old builder interleaved prompt/photo identically for everyone. Each
#  profile now carries its own running order; the hero photo is still forced
#  first, and anything the layout does not consume is flushed after it so no
#  photo or answer is ever dropped.
$oldLoop = @'
      let pi = 1, qi = 0, det = false;
      while (pi < person.n || qi < person.prompts.length) {
        if (qi < person.prompts.length) { feed.push(Object.assign({}, blank, { isPrompt: true, q: person.prompts[qi][0], a: person.prompts[qi][1] })); qi++; }
        if (qi === 2 && !det) { feed.push(details()); det = true; }
        if (pi < person.n) { feed.push(Object.assign({}, blank, { isPhoto: true, bg: shot(person, pi), count: (pi + 1) + ' / ' + person.n })); pi++; }
      }
'@
$newLoop = @'
      let pi = 1, qi = 0, det = false;
      const pushPhoto = () => { feed.push(Object.assign({}, blank, { isPhoto: true, bg: shot(person, pi), count: (pi + 1) + ' / ' + person.n })); pi++; };
      const pushPrompt = () => { feed.push(Object.assign({}, blank, { isPrompt: true, q: person.prompts[qi][0], a: person.prompts[qi][1] })); qi++; };
      const order = person.layout || ['q', 'p', 'q', 'd', 'p', 'q', 'p'];
      order.forEach(tok => {
        if (tok === 'q' && qi < person.prompts.length) pushPrompt();
        else if (tok === 'p' && pi < person.n) pushPhoto();
        else if (tok === 'd' && !det) { feed.push(details()); det = true; }
      });
      while (pi < person.n || qi < person.prompts.length) {
        if (qi < person.prompts.length) pushPrompt();
        if (pi < person.n) pushPhoto();
      }
'@
if (-not $doc.Contains($oldLoop)) { throw "deck builder loop not found" }
$doc = $doc.Replace($oldLoop, $newLoop)
Write-Output ("roster people: {0} | layouts: {1}" -f ([regex]::Matches($doc,"name:'")).Count, ([regex]::Matches($doc,'layout:\[')).Count)

# ── 5j. the roster is written as .jpg; older markup still asks for .png ───────
$doc = [regex]::Replace($doc, '(assets/people/[a-z]+-\d+)\.png', '$1.jpg')

# ── 5k. surface the connection on the phone root, for the bar layer to read ───
#  hasConnection, lastMessage and at.chat already exist in renderVals; putting
#  them on the root as attributes lets the bar layer show the chat strip
#  without duplicating any of the app's state.
$phoneTag = '<div dir="{{ dir }}" data-tg-phone="1"'
if (-not $doc.Contains($phoneTag)) { throw "phone root not found" }
$doc = $doc.Replace($phoneTag, '<div dir="{{ dir }}" data-tg-phone="1" data-tg-conn="{{ hasConnection }}" data-tg-last="{{ lastMessage }}" data-tg-chat="{{ at.chat }}"')

#  a hidden button the bar layer can click to open the chat, so navigation
#  stays the app's job exactly as it does for the tab bar
$anchor = '<div class="tg-scroll" style="flex:1;overflow-y:auto;overflow-x:hidden;position:relative">'
if ($doc.Contains($anchor)) {
    $doc = $doc.Replace($anchor, '<button id="tg-open-chat" style="display:none" sc-camel-on-click="{{ go.chat }}"></button>' + "`n        " + $anchor)
} else { throw "scroll container not found for the chat hook" }

# ── 5l. the chat's back arrow goes to the deck, not the slot list ─────────────
#  Leaving a conversation you want the people, not a list with one row on it.
$backTog = 'sc-camel-on-click="{{ go.together }}" aria-label="Back"'
$hits = ([regex]::Matches($doc, [regex]::Escape($backTog))).Count
if ($hits -ne 1) { throw "expected exactly one chat back button, found $hits" }
$doc = $doc.Replace($backTog, 'sc-camel-on-click="{{ go.discover }}" aria-label="Back"')

# ── 5m. the new mark and wordmark ─────────────────────────────────────────────
#  The splash lockup: the mark draws itself in, the interlock appears as it
#  settles, and the wordmark sits directly beneath with the rings as its "o".
$lockup = [System.IO.File]::ReadAllText("$scratch\splash-lockup.html", [System.Text.Encoding]::UTF8)
$ls = $doc.IndexOf('<div style="width:min(66vw,214px);animation:tg-lift')
$le = $doc.IndexOf('>its all about the effort</p>')
if ($ls -lt 0 -or $le -lt $ls) { throw "splash lockup bounds not found ($ls, $le)" }
$le = $le + '>its all about the effort</p>'.Length
$doc = $doc.Substring(0, $ls) + $lockup.Trim() + $doc.Substring($le)

#  every small mark elsewhere in the app points at the new icon
$markSvg = [System.IO.File]::ReadAllText("$repoDir\mark.svg", [System.Text.Encoding]::UTF8)
$markSvg = [regex]::Replace($markSvg, '(?s)<!--.*?-->', '')
$markSvg = [regex]::Replace($markSvg, '\s*\r?\n\s*', ' ').Trim()
$markUri = 'data:image/svg+xml;charset=utf-8,' + [uri]::EscapeDataString($markSvg)
$oldMark = 'src="2e1211b0-91e5-44d2-a0a0-5f552f929418"'
$markHits = ([regex]::Matches($doc, [regex]::Escape($oldMark))).Count
$doc = $doc.Replace($oldMark, 'src="' + $markUri + '"')
Write-Output ("small marks repointed: {0}" -f $markHits)

#  the browser chrome colour follows the ground
$doc = $doc.Replace('<meta name="theme-color" content="#14101A">', '<meta name="theme-color" content="#E3E1D8">')

# ── 5n. two stray closers in the source's feed loop ───────────────────────────
#  After the prompt card, a spare </div></sc-if> closes the feed item and the
#  deck early, which ends .tg-scroll and leaves every later screen outside it.
$stray = '(</sc-if>)\s*</div>\s*</sc-if>(\s*<sc-if value="\{\{ b\.isDetails \}\}">)'
$sm = ([regex]::Matches($doc, $stray)).Count
if ($sm -ne 1) { throw "expected one stray closer pair before b.isDetails, found $sm" }
$doc = [regex]::Replace($doc, $stray, '$1$2')
# ── 5o. the round buttons over photos and answers ─────────────────────────────
#  The blur layer ignored the round clip and showed as a square; the buttons
#  are round themselves now, with no blur. The heart takes the rose ink.
$oldBtn = 'style="width:100%;height:100%;border-radius:2px;border:0;background:rgba(227,225,216,.6);backdrop-filter:blur(14px);'
$bh = ([regex]::Matches($doc, [regex]::Escape($oldBtn))).Count
if ($bh -lt 4) { throw "expected the round overlay buttons, found $bh" }
$doc = $doc.Replace($oldBtn, 'style="width:100%;height:100%;border-radius:999px;border:0;background:#FBFAF6;box-shadow:inset 0 0 0 1px rgba(28,37,54,.06);')
$heart = 'fill="none" stroke="#1C2536" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M20.8 5.6a5.2 5.2'
$hh = ([regex]::Matches($doc, [regex]::Escape($heart))).Count
if ($hh -lt 3) { throw "expected the like hearts, found $hh" }
$doc = $doc.Replace($heart, 'fill="none" stroke="#E4485B" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M20.8 5.6a5.2 5.2')
#  every round button wears the same glass and the same soft lift, whether it
#  sits on a photo or on an answer card
$spanOld = @(
  'width:44px;height:44px;border-radius:999px;overflow:hidden;display:block;box-shadow:0 6px 18px rgba(0,0,0,.32)"',
  'width:44px;height:44px;border-radius:999px;overflow:hidden;display:block"'
)
$lift = 'width:44px;height:44px;border-radius:999px;overflow:hidden;display:block;box-shadow:0 4px 14px rgba(28,37,54,.2)"'
$sn = 0
foreach ($s in $spanOld) { $sn += ([regex]::Matches($doc, [regex]::Escape($s))).Count; $doc = $doc.Replace($s, $lift) }
if ($sn -lt 4) { throw "expected four round button holders, found $sn" }Write-Output ("round buttons: {0} | rose hearts: {1}" -f $bh, $hh)
# ── 5p. the swipe: left moves on, right does nothing, and it never sticks ─────
#  Liking is only ever the heart. The release is caught wherever it happens
#  (pointer capture plus a window fallback), so the card can't be left hanging.
$swOld = @(
  @('this._sx = e.clientX; this._sy = e.clientY; this._dir = null; this._dx = 0;',
    "this._sx = e.clientX; this._sy = e.clientY; this._dir = null; this._dx = 0;`n    if (!this._upWin) { this._upWin = () => this.deckUp(); }`n    window.removeEventListener('pointerup', this._upWin); window.removeEventListener('pointercancel', this._upWin);`n    window.addEventListener('pointerup', this._upWin); window.addEventListener('pointercancel', this._upWin);"),
  @("    this._dx = dx;`n    const d = this.deck();`n    if (d) { d.style.transition = 'none'; d.style.transform = 'translateX(' + dx + 'px) rotate(' + (dx / 30) + 'deg)'; }",
    "    const vx = dx > 0 ? Math.min(28, dx * 0.18) : dx;   // right: a small give, nothing more`n    this._dx = dx;`n    const d = this.deck();`n    if (d) { d.style.transition = 'none'; d.style.transform = 'translateX(' + vx + 'px) rotate(' + (vx / 30) + 'deg)'; }"),
  @("    if (l) l.style.opacity = clamp(dx / 90);", "    if (l) l.style.opacity = '0';"),
  @("    const dx = this._dx || 0, dragged = this._dir === 'x';",
    "    if (this._upWin) { window.removeEventListener('pointerup', this._upWin); window.removeEventListener('pointercancel', this._upWin); }`n    const dx = this._dx || 0, dragged = this._dir === 'x';"),
  @("    if (dx >= 80) setTimeout(() => { this._justDragged = false; this.openLike('photo'); }, 130);`n", ""),
  @("    setTimeout(() => {`n      this.setState({ personIdx: this.state.personIdx + 1 }, () => {",
    "    setTimeout(() => { this._passing = false; }, 900);   // never stay locked`n    setTimeout(() => {`n      this.setState({ personIdx: this.state.personIdx + 1 }, () => {")
)
foreach ($p in $swOld) {
  $n = $doc.Split([string[]]@($p[0]), [StringSplitOptions]::None).Length - 1
  if ($n -ne 1) { throw ("swipe patch anchor found {0} times: {1}" -f $n, $p[0].Substring(0, [math]::Min(50, $p[0].Length))) }
  $doc = $doc.Replace($p[0], $p[1])
}
#  a drag on the deck shouldn't select text or pick up an image
$deckTag = 'data-tg-deck="1" style="display:flex;flex-direction:column;gap:14px;touch-action:pan-y"'
if (-not $doc.Contains($deckTag)) { throw "deck tag not found" }
$doc = $doc.Replace($deckTag, 'data-tg-deck="1" style="display:flex;flex-direction:column;gap:14px;touch-action:pan-y;user-select:none;-webkit-user-select:none;-webkit-user-drag:none" ondragstart="return false"')
$doc = $doc.Replace('<p style="margin:0">Swipe left, or tap the cross, to move on.</p>', '<p style="margin:0">Swipe left, or tap the cross, to move on. The heart is how you like.</p>')
# ── 5q. the toast ─────────────────────────────────────────────────────────────
#  It came through the palette as dark ink on a dark bar over the buttons. It is
#  now a light note under the header, and says nothing when there is nothing
#  worth saying.
$toastOld = 'style="position:absolute;bottom:96px;inset-inline:20px;z-index:12;background:rgba(32,26,44,.95);border:1px solid rgba(28,37,54,.16);color:#1C2536;border-radius:999px;padding:13px 20px;font-size:15px;font-style:normal;text-align:center;box-shadow:var(--shadow-lg);animation:tg-up .25s ease">{{ toast }}'
if (-not $doc.Contains($toastOld)) { throw "toast markup not found" }
$doc = $doc.Replace($toastOld, 'style="position:absolute;top:calc(env(safe-area-inset-top,0px) + 64px);inset-inline:0;z-index:30;display:flex;justify-content:center;pointer-events:none;padding:0 20px;animation:tg-in .25s ease"><span style="background:#FBFAF6;color:#1C2536;border:1px solid rgba(28,37,54,.08);border-radius:3px;padding:9px 14px;font-size:13.5px;line-height:1.35;text-align:center;box-shadow:0 6px 20px rgba(28,37,54,.14);max-width:320px">{{ toast }}</span>')
foreach ($quiet in @("this.toast('Signed in'); ", "this.toast('Signed in as Daniel'); ", "this.toast('Setup skipped'); ")) {
  $doc = $doc.Replace($quiet, '')
}
foreach ($loud in @("'Signed in'", "'Signed in as Daniel'", "'Setup skipped'")) {
  if ($doc.Contains("this.toast($loud)")) { Write-Output "note: toast $loud still present in another form" }
}
# ── 5r. Preferences, rethought ────────────────────────────────────────────────
#  Grouped setting cards, a live count of who fits, a two-handle age range,
#  switches, intent tiles, and a locked premium group. Changes save themselves.
$ps = $doc.IndexOf('<sc-if value="{{ at.prefs }}">')
$pe = $doc.IndexOf('<sc-if value="{{ at.profile }}">')
if ($ps -lt 0 -or $pe -lt $ps) { throw "preferences screen bounds not found ($ps, $pe)" }
$doc = $doc.Substring(0, $ps) + [System.IO.File]::ReadAllText("$scratch\prefs-screen.html", [System.Text.Encoding]::UTF8).TrimStart() + $doc.Substring($pe)

$vs = $doc.IndexOf('prefs: st.prefs, distLabel:')
$ve = $doc.IndexOf("savePrefs: () => {", $vs)
if ($vs -lt 0 -or $ve -lt $vs) { throw "preference values not found ($vs, $ve)" }
$ve = $doc.IndexOf("`n", $ve) + 1
$doc = $doc.Substring(0, $vs) + [System.IO.File]::ReadAllText("$scratch\prefs-vals.js.txt", [System.Text.Encoding]::UTF8).Trim() + "`n" + $doc.Substring($ve)

$hs = $doc.IndexOf('</helmet>')
if ($hs -lt 0) { throw "helmet close not found" }
$doc = $doc.Substring(0, $hs) + [System.IO.File]::ReadAllText("$scratch\prefs-style.html", [System.Text.Encoding]::UTF8) + $doc.Substring($hs)

$prefState = "prefs: { ageMin: 26, ageMax: 36, dist: 15, seek: ['Women'], intent: 'A relationship', kids: 'Any' },"
if (-not $doc.Contains($prefState)) { throw "preference state not found" }
$doc = $doc.Replace($prefState, "prefs: { ageMin: 26, ageMax: 36, dist: 15, seek: ['Women'], intent: 'A relationship', kids: 'Any', strictDist: true, strictAge: false, verifiedOnly: false },")

$setOld = "      prefKids: e => this.setPref('kids', e.target.value)"
if (-not $doc.Contains($setOld)) { throw "preference setters not found" }
$doc = $doc.Replace($setOld, $setOld + ",`n      strictDist: () => this.setPref('strictDist', !st.prefs.strictDist),`n      strictAge: () => this.setPref('strictAge', !st.prefs.strictAge),`n      verifiedOnly: () => this.setPref('verifiedOnly', !st.prefs.verifiedOnly)")
$doc = $doc.Replace("ageMin: e => this.setPref('ageMin', Math.min(+e.target.value, st.prefs.ageMax - 1)),", "ageMin: e => { const v = Math.min(+e.target.value, st.prefs.ageMax - 1); e.target.value = v; this.setPref('ageMin', v); },")
$doc = $doc.Replace("ageMax: e => this.setPref('ageMax', Math.max(+e.target.value, st.prefs.ageMin + 1)),", "ageMax: e => { const v = Math.max(+e.target.value, st.prefs.ageMin + 1); e.target.value = v; this.setPref('ageMax', v); },")

$spOld = "setPref(k, v) { this.setState({ prefs: Object.assign({}, this.state.prefs, { [k]: v }), prefsDirty: true, prefsSaved: false }); }"
if (-not $doc.Contains($spOld)) { throw "setPref not found" }
$doc = $doc.Replace($spOld, "setPref(k, v) {`n    this.setState({ prefs: Object.assign({}, this.state.prefs, { [k]: v }), prefsDirty: true, prefsSaved: false });`n    clearTimeout(this._prefSave);`n    this._prefSave = setTimeout(() => this.setState({ prefsDirty: false, prefsSaved: true }), 650);`n  }")

$heNew = [ordered]@{
  'Discovery'='גילוי'; 'Maximum distance'='מרחק מקסימלי'; 'Only within this distance'='רק בטווח הזה';
  'Otherwise we show a few people just past it when you run out.'='אחרת, כשייגמרו האנשים, נראה לכם כמה שקצת מעבר.';
  'Age range'='טווח גילים'; 'Only this age range'='רק בטווח הגילים הזה'; 'Otherwise a year either side can show up.'='אחרת יכולים להופיע גם שנה לכאן או לכאן.';
  'Show me'='הראו לי'; 'What they are here for'='מה הם מחפשים כאן'; 'Open to anything'='פתוחים להכול'; 'Something that lasts'='משהו שנשאר';
  'Seeing where it goes'='לראות לאן זה הולך'; 'Kids'='ילדים'; 'Trust'='אמון'; 'Verified profiles only'='רק פרופילים מאומתים';
  'People who passed the selfie check.'='אנשים שעברו את בדיקת הסלפי.'; 'Finer filters'='סינון מדויק יותר'; 'Premium'='פרימיום';
  'Height'='גובה'; 'Education'='השכלה'; 'Languages'='שפות'; 'Drinking and smoking'='שתייה ועישון';
  'Finer filters are in the next pass'='סינון מדויק יותר יגיע בגרסה הבאה'; 'Women'='נשים'; 'Men'='גברים'; 'Everyone'='כולם';
  'Any'='הכול'; 'A relationship'='קשר'; 'Open to a relationship'='פתוחים לקשר'; 'Has kids'='יש ילדים'; 'Wants kids'='רוצים ילדים'; 'Does not want kids'='לא רוצים ילדים'
}
$heAdd = ''
foreach ($k in $heNew.Keys) { if (-not $doc.Contains('"' + $k + '":')) { $heAdd += '    "' + $k + '": "' + $heNew[$k] + '",' + "`n" } }
$doc = $doc.Replace('    "Preferences saved": ', $heAdd + '    "Preferences saved": ')
Write-Output ("preferences rebuilt; hebrew strings added: {0}" -f ($heAdd -split "`n").Where({ $_ }).Count)
# ── 5s. The basics, warmer ────────────────────────────────────────────────────
#  Same fields, wheels and checks; the dropdowns become tiles and a segmented
#  control, the fields sit on a card, and the step shows as a progress rule.
$bs = $doc.IndexOf('<sc-if value="{{ at.basics }}">')
$be = $doc.IndexOf('<sc-if value="{{ at.photos }}">')
if ($bs -lt 0 -or $be -lt $bs) { throw "basics screen bounds not found ($bs, $be)" }
$basics = [System.IO.File]::ReadAllText("$scratch\basics-screen.html", [System.Text.Encoding]::UTF8).TrimStart().Replace('src="2e1211b0-91e5-44d2-a0a0-5f552f929418"', 'src="' + $markUri + '"')
$doc = $doc.Substring(0, $bs) + $basics + $doc.Substring($be)
$heB = [ordered]@{ 'Step 1 of 3'='שלב 1 מתוך 3'; 'The basics'='הבסיס'; 'A minute of you. Only your first name and your age are ever shown.'='דקה עליכם. רק השם הפרטי והגיל מוצגים אי־פעם.';
  'You'='אתם'; 'First name'='שם פרטי'; 'Last name'='שם משפחה'; 'Name tag'='תג שם'; 'Birthday'='יום הולדת'; 'I am'='אני';
  'Man'='גבר'; 'Woman'='אישה'; 'Still working it out'='עוד מבררים'; 'No pressure either way'='בלי לחץ לשום כיוון'; 'What you are here for'='מה אתם מחפשים כאן' }
$heAdd = ''
foreach ($k in $heB.Keys) { if (-not $doc.Contains('"' + $k + '":')) { $heAdd += '    "' + $k + '": "' + $heB[$k] + '",' + "`n" } }
$doc = $doc.Replace('    "Preferences saved": ', $heAdd + '    "Preferences saved": ')
# ── 5t. breathing room above every header ─────────────────────────────────────
#  Titles sat about 10px under the phone's top edge, tucked into the corner.
$tops = @(
  @('style="padding:var(--space-2) var(--space-4) var(--space-8);', 'style="padding:30px var(--space-4) var(--space-8);', 4),
  @('backdrop-filter:blur(10px);padding:var(--space-2) var(--space-4) var(--space-3)"', 'backdrop-filter:blur(10px);padding:30px var(--space-4) var(--space-3)"', 1),
  @('backdrop-filter:blur(10px);padding:var(--space-2) var(--space-3);display:flex', 'backdrop-filter:blur(10px);padding:26px var(--space-3) var(--space-2);display:flex', 4),
  @('padding:var(--space-6);padding-block-end:70px;', 'padding:var(--space-6);padding-block-start:36px;padding-block-end:70px;', 3),
  @('flex-direction:column;padding:var(--space-6);animation:', 'flex-direction:column;padding:var(--space-6);padding-block-start:36px;animation:', 1),
  @('padding:var(--space-6) var(--space-4) 150px;', 'padding:36px var(--space-4) 150px;', 1),
  @('flex-direction:column;padding:24px 20px 70px;', 'flex-direction:column;padding:36px 20px 70px;', 1)
)
foreach ($t in $tops) {
  $n = ([regex]::Matches($doc, [regex]::Escape($t[0]))).Count
  if ($n -lt $t[2]) { throw ("header spacing: expected {0}+ of '{1}', found {2}" -f $t[2], $t[0].Substring(0, 40), $n) }
  $doc = $doc.Replace($t[0], $t[1])
}
# ── 5u. proper capitals ───────────────────────────────────────────────────────
#  The original look forced every letter in the phone to lowercase. Text now
#  shows as written: sentence case, names capitalised. Labels that were written
#  in Title Case for the old rule are put into sentence case.
$caseRules = @(
  @('[data-tg-phone] *{text-transform:lowercase !important}', '[data-tg-phone] input::placeholder,[data-tg-phone] textarea::placeholder{text-transform:none}'),
  @('letter-spacing:-.018em;text-transform:lowercase}', 'letter-spacing:-.018em}'),
  @('.btn{text-transform:lowercase;', '.btn{'),
  @('font-family:var(--font-body) !important;text-transform:lowercase}', 'font-family:var(--font-body) !important}')
)
foreach ($c in $caseRules) {
  if (-not $doc.Contains($c[0])) { throw ("casing rule not found: {0}" -f $c[0]) }
  $doc = $doc.Replace($c[0], $c[1])
}
$sentence = [ordered]@{
  '>Phone Number<' = '>Phone number<'; '>Photos And Prompts<' = '>Photos and prompts<'; '>Prove You Are You<' = '>Prove you are you<';
  '>Start Here<' = '>Start here<'; '>Together · All Set<' = '>Together · All set<'; '>Together · Step 2 Of 3<' = '>Together · Step 2 of 3<';
  '>Together · Step 3 Of 3<' = '>Together · Step 3 of 3<'; '>Welcome Back<' = '>Welcome back<'; '>You Are In,' = '>You are in,';
  '>why you two<' = '>Why you two<'; 'font-style:italic">you</div>' = 'font-style:italic">You</div>'
}
foreach ($k in $sentence.Keys) {
  if (-not $doc.Contains($k)) { throw ("sentence-case target not found: {0}" -f $k) }
  $doc = $doc.Replace($k, $sentence[$k])
}
#  any other Title Case label marked for the old casing, e.g. "Date Of Birth"
$doc = [regex]::Replace($doc, '(<(?:label|span|h\d|p|div|button)[^>]*class="[^"]*tg-cased[^"]*"[^>]*>)([^<{}]+)(<)', {
  param($m)
  $txt = $m.Groups[2].Value
  $words = $txt -split ' '
  for ($w = 1; $w -lt $words.Count; $w++) {
    if ($words[$w] -cmatch '^[A-Z][a-z]+$' -and $words[$w] -notin @('Maya','Daniel','Together','Premium','Google','Apple','ILS','Yael','Ori')) { $words[$w] = $words[$w].ToLower() }
  }
  $m.Groups[1].Value + ($words -join ' ') + $m.Groups[3].Value
})

#  sentences in the source that start lowercase after a full stop
$markup = $doc.Substring(0, $doc.IndexOf('class Component'))
$fixes = @{}
foreach ($m in [regex]::Matches($markup, '>([^<>{}]*[a-z][\.\?!]\s+[a-z][^<>{}]*)<')) {
  $orig = $m.Groups[1].Value
  $fixed = [regex]::Replace($orig, '([a-z][\.\?!]\s+)([a-z])', { param($x) $x.Groups[1].Value + $x.Groups[2].Value.ToUpper() })
  if ($fixed -cne $orig) { $fixes[$orig] = $fixed }
}
foreach ($k in $fixes.Keys) { $doc = $doc.Replace($k, $fixes[$k]) }
Write-Output ("sentence starts capitalised: {0}" -f $fixes.Count)
#  profile answers and the intent chip are written to follow on from their
#  question, so they start lowercase in the data; shown alone, they get a capital
$cap1 = "(s => s ? s.charAt(0).toUpperCase() + s.slice(1) : s)"
foreach ($p in @(@('a: person.prompts[qi][1] }', "a: $cap1(person.prompts[qi][1]) }"), @('intentChip: person.intent,', "intentChip: $cap1(person.intent),"))) {
  if (-not $doc.Contains($p[0])) { throw ("deck text not found: {0}" -f $p[0]) }
  $doc = $doc.Replace($p[0], $p[1])
}
$heKeys = 0
foreach ($m in [regex]::Matches($doc, "(?m)^\s*""([a-z][^""]{2,})"":\s*""")) {
  $k = $m.Groups[1].Value
  $kCap = $k.Substring(0, 1).ToUpper() + $k.Substring(1)
  $isAnswer = $doc.Contains("'" + $k + "']") -or $doc.Contains("'" + $k + "' ]")
  if ($isAnswer -and -not $doc.Contains('"' + $kCap + '":')) { $doc = $doc.Replace('"' + $k + '":', '"' + $kCap + '":'); $heKeys++ }
}
Write-Output ("hebrew keys capitalised: {0}" -f $heKeys)
#  text boxes start with a capital: names capitalise each word, free text its
#  first letter; logins and codes are left exactly as typed
$capAttrs = [ordered]@{
  'sc-camel-on-input="{{ set.name }}"' = 'data-tg-cap="words" autocapitalize="words"';
  'sc-camel-on-input="{{ set.last }}"' = 'data-tg-cap="words" autocapitalize="words"';
  'sc-camel-on-input="{{ set.about }}"' = 'data-tg-cap="first" autocapitalize="sentences"';
  'sc-camel-on-input="{{ set.draft }}"' = 'data-tg-cap="first" autocapitalize="sentences"';
  'sc-camel-on-input="{{ set.customQ }}"' = 'data-tg-cap="first" autocapitalize="sentences"';
  'sc-camel-on-input="{{ set.qDraft }}"' = 'data-tg-cap="first" autocapitalize="sentences"';
  'sc-camel-on-input="{{ set.likeComment }}"' = 'data-tg-cap="first" autocapitalize="sentences"';
  'sc-camel-on-input="{{ set.vdNote }}"' = 'data-tg-cap="first" autocapitalize="sentences"';
  'sc-camel-on-input="{{ set.email }}"' = 'autocapitalize="none" autocorrect="off" spellcheck="false"';
  'sc-camel-on-input="{{ set.handle }}"' = 'autocapitalize="none" autocorrect="off" spellcheck="false"';
  'sc-camel-on-input="{{ set.coupon }}"' = 'autocapitalize="characters" autocorrect="off" spellcheck="false"'
}
foreach ($k in $capAttrs.Keys) {
  if (-not $doc.Contains($k)) { throw ("input not found for capitals: {0}" -f $k) }
  $doc = $doc.Replace($k, $capAttrs[$k] + ' ' + $k)
}

# ── 5v. Discover, built around the first photo ────────────────────────────────
#  The first photo leads, full width; the page and cards take its colours; the
#  other photos sit below as tiles that open full screen. Every photo and every
#  answer can still be liked on its own.
function Swap1([string]$from, [string]$to, [string]$what) {
  $n = $script:doc.Split([string[]]@($from), [StringSplitOptions]::None).Length - 1
  if ($n -ne 1) { throw ("discover: expected one '{0}', found {1}" -f $what, $n) }
  $script:doc = $script:doc.Replace($from, $to)
}
$discScratch = $scratch
Swap1 'static PEOPLE = [' ([System.IO.File]::ReadAllText("$discScratch\palette.js.txt", [System.Text.Encoding]::UTF8).Trim() + "`n  static PEOPLE = [") 'people list'
Swap1 '    const cats = Component.QCATS;' ([System.IO.File]::ReadAllText("$discScratch\discover-vals.js.txt", [System.Text.Encoding]::UTF8).TrimEnd() + "`n`n    const cats = Component.QCATS;") 'question categories'
Swap1 'noPerson: !person, feed,' 'noPerson: !person, feed, dv,' 'feed binding'

$fs = $doc.IndexOf('<sc-for list="{{ feed }}" as="b"')
$fe = $doc.IndexOf('<div style="text-align:center;padding:var(--space-4) 0 0;', $fs)
if ($fs -lt 0 -or $fe -lt $fs) { throw "discover feed bounds not found ($fs, $fe)" }
function ProfileBlocks([string]$src) {
  $h21 = '<svg width="21" height="21" sc-camel-view-box="0 0 24 24" fill="none" stroke="#E4485B" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M20.8 5.6a5.2 5.2 0 0 0-7.4 0L12 7l-1.4-1.4a5.2 5.2 0 1 0-7.4 7.4L12 21.5l8.8-8.5a5.2 5.2 0 0 0 0-7.4z"></path></svg>'
  $h15 = $h21.Replace('width="21" height="21"', 'width="15" height="15"').Replace('stroke-width="2.2"', 'stroke-width="2.4"')
  return [System.IO.File]::ReadAllText("$discScratch\profile-blocks.html", [System.Text.Encoding]::UTF8).Trim().Replace('__S__', $src).Replace('__HEART21__', $h21).Replace('__HEART15__', $h15)
}
$doc = $doc.Substring(0, $fs) + (ProfileBlocks 'dv') + "`n                      " + $doc.Substring($fe)
Swap1 "<sc-if value=""{{ at.discover }}"">`n            <div style=""animation:tg-in .3s ease"">" "<sc-if value=""{{ at.discover }}"">`n            <div class=""tgd-root"" style=""--pv:{{ dv.pal.v }};--pd:{{ dv.pal.d }};--pl:{{ dv.pal.l }};animation:tg-in .3s ease"">`n              <div class=""tgd-backdrop"" aria-hidden=""true""><div class=""tgd-backdrop-img"" style=""background:{{ dv.hero.bg }}""></div></div>" 'discover root'
Swap1 '<div style="position:sticky;top:0;z-index:2;background:color-mix(in srgb,var(--color-bg) 88%,transparent);backdrop-filter:blur(10px);padding:30px' '<div class="tgd-bar" style="position:sticky;top:0;z-index:2;background:color-mix(in srgb,var(--color-bg) 88%,transparent);backdrop-filter:blur(10px);padding:30px' 'discover header'
Swap1 '<sc-if value="{{ overlay.like }}">' ([System.IO.File]::ReadAllText("$discScratch\discover-viewer.html", [System.Text.Encoding]::UTF8).Trim() + "`n`n        <sc-if value=""{{ overlay.like }}"">") 'like sheet'
Swap1 "showDock: screen === 'discover' && st.mode === 'single' && !!person && !st.overlay," "showDock: screen === 'discover' && st.mode === 'single' && !!person && !st.overlay && st.viewer == null," 'pass button binding'
Swap1 'personIdx: 0,' 'personIdx: 0, viewer: null, likeIdx: 0,' 'initial state'
Swap1 'openLike(target) {' 'openLike(target, idx, extra) {' 'openLike'
Swap1 "this.setState({ overlay: 'like', likeTarget: target, likeComment: '' });" "this.setState({ overlay: 'like', likeTarget: target, likeIdx: idx || 0, likeExtra: extra || null, likeComment: '', viewer: null });" 'openLike state'
Swap1 "(person ? person.prompts[0][0] : 'The way to win me over is')" "(st.likeExtra && st.likeExtra.kicker ? st.likeExtra.kicker : person ? (person.prompts[st.likeIdx] || person.prompts[0])[0] : 'The way to win me over is')" 'like kicker'
Swap1 "(person ? person.prompts[0][1] : " "(st.likeExtra && st.likeExtra.text ? st.likeExtra.text : person ? (s => s.charAt(0).toUpperCase() + s.slice(1))((person.prompts[st.likeIdx] || person.prompts[0])[1]) : " 'like text'
Swap1 "likeIsPhoto: st.likeTarget === 'photo'," "likeIsPhoto: st.likeTarget === 'photo', likePhotoBg: (st.likeExtra && st.likeExtra.src) ? 'center/cover no-repeat url(' + st.likeExtra.src + ')' : shot(person, st.likeIdx || 0)," 'like photo flag'
Swap1 '<div style="width:100%;height:100%;background:center/cover no-repeat url(assets/people/maya-1.jpg)"></div>' '<div style="width:100%;height:100%;background:{{ likePhotoBg }}"></div>' 'like sheet photo'
Swap1 '<span style="font-size:13px;font-style:italic;color:#D6B0EC">{{ likeTargetKicker }}</span>' '<span style="font-size:13px;font-style:italic;color:#57304F">{{ likeTargetKicker }}</span>' 'like kicker colour'
Swap1 'this.setState({ personIdx: this.state.personIdx + 1 }, () => {' 'this.setState({ personIdx: this.state.personIdx + 1, viewer: null }, () => {' 'pass person'
Swap1 'data-tg-chat="{{ at.chat }}"' 'data-tg-chat="{{ at.chat }}" data-tg-viewer="{{ dv.viewerOpen }}" data-tg-ov="{{ dv.ovOpen }}"' 'phone data hooks'
$hs2 = $doc.IndexOf('</helmet>')
$doc = $doc.Substring(0, $hs2) + [System.IO.File]::ReadAllText("$discScratch\discover-style.html", [System.Text.Encoding]::UTF8) + $doc.Substring($hs2)
$heD = [ordered]@{ 'More of'='עוד של'; 'Tap to open'='הקישו לפתיחה'; 'About'='על'; 'Like this photo'='לייק לתמונה הזו'; 'Like this answer'='לייק לתשובה הזו' }
$heAdd = ''
foreach ($k in $heD.Keys) { if (-not $doc.Contains('"' + $k + '":')) { $heAdd += '    "' + $k + '": "' + $heD[$k] + '",' + "`n" } }
$doc = $doc.Replace('    "Preferences saved": ', $heAdd + '    "Preferences saved": ')
Write-Output "discover rebuilt around the first photo"

# ── 5w. Edit profile, laid out the way people see it ──────────────────────────
#  One list in the profile's real order: tap an item to edit it, hold to lift
#  it and drag it into place. Up to 6 photos, 2 videos, 6 prompts, 1 voice note.
#  A View tab shows exactly what Discover shows.
Swap1 "['splash','auth','login','otp','basics','photos','verify','welcome','discover','likes','together','prefs','profile','chat'," "['splash','auth','login','otp','basics','photos','verify','welcome','discover','likes','together','prefs','profile','editprofile','chat'," 'screen list'
Swap1 "{ label: 'Edit profile', meta: st.form.handle ? '@' + st.form.handle : 'Name, photos, prompts', onClick: () => this.nav('basics') }" "{ label: 'Edit profile', meta: 'Photos, videos, prompts, voice', onClick: () => this.nav('editprofile', { epMode: 'edit' }) }" 'profile menu'
$editor = [System.IO.File]::ReadAllText("$discScratch\editor-screen.html", [System.Text.Encoding]::UTF8).Trim().Replace('__VIEW_BLOCKS__', (ProfileBlocks 'ep.view'))
Swap1 '<sc-if value="{{ at.settings }}">' ($editor + "`n`n          <sc-if value=""{{ at.settings }}"">") 'settings screen'
Swap1 '<sc-if value="{{ overlay.like }}">' ([System.IO.File]::ReadAllText("$discScratch\editor-sheet.html", [System.Text.Encoding]::UTF8).Trim() + "`n`n        <sc-if value=""{{ overlay.like }}"">") 'like sheet (editor)'
Swap1 '  passPerson() {' ([System.IO.File]::ReadAllText("$discScratch\profile-methods.js.txt", [System.Text.Encoding]::UTF8).TrimEnd() + "`n`n  passPerson() {") 'passPerson'
$meState = "playing: null, epMode: 'edit', epSheet: null, epQ: '', epA: '', epRec: 'idle', epSecs: 12, epFlash: null, " +
  "me: { work: 'Product designer', height: '180 cm', home: 'Tel Aviv', items: [" +
  "{ id: 'm1', kind: 'photo', src: 'assets/people/daniel-1.jpg' }, " +
  "{ id: 'm2', kind: 'prompt', q: 'A perfect Sunday', a: 'Long run, longer breakfast, and a nap I will deny taking.' }, " +
  "{ id: 'm3', kind: 'photo', src: 'assets/people/daniel-2.jpg' }, " +
  "{ id: 'm4', kind: 'voice', q: 'My go-to karaoke song', dur: '0:14', secs: 14 }, " +
  "{ id: 'm5', kind: 'photo', src: 'assets/people/daniel-4.jpg' }, " +
  "{ id: 'm6', kind: 'video', src: 'assets/people/daniel-6.jpg', dur: '0:14', secs: 14 }, " +
  "{ id: 'm7', kind: 'prompt', q: 'I am looking for', a: 'Someone who reads the menu out loud and still orders the same thing.' }, " +
  "{ id: 'm8', kind: 'photo', src: 'assets/people/daniel-8.jpg' }" +
  "] }, "
Swap1 'personIdx: 0, viewer: null, likeIdx: 0,' ('personIdx: 0, viewer: null, likeIdx: 0, ' + $meState) 'editor state'
Swap1 'noPerson: !person, feed, dv,' 'noPerson: !person, feed, dv, ep,' 'editor binding'
#  the profile screen shows the real first photo instead of an initial
Swap1 'background:rgba(28,37,54,.10);box-shadow:inset 0 0 0 1px rgba(28,37,54,.16);display:grid;place-items:center;color:#1C2536;font-family:var(--font-heading);font-size:30px">D</div>' 'background:{{ ep.view.hero.bg }};box-shadow:0 0 0 3px #FBFAF6,0 6px 16px rgba(28,37,54,.2)"></div>' 'profile avatar'
$hs3 = $doc.IndexOf('</helmet>')
$doc = $doc.Substring(0, $hs3) + [System.IO.File]::ReadAllText("$discScratch\editor-style.html", [System.Text.Encoding]::UTF8) + $doc.Substring($hs3)
$heE = [ordered]@{
  'Edit profile'='עריכת פרופיל'; 'Done'='סיום'; 'Edit'='עריכה'; 'View'='תצוגה'; 'Tap to edit · Hold and drag to move'='הקישו לעריכה · החזיקו וגררו להזזה'; 'Size on your profile'='גודל בפרופיל'; 'Main photo · drop a photo here to swap'='תמונה ראשית · שחררו כאן תמונה כדי להחליף';
  'Add to your profile'='הוספה לפרופיל'; 'My vitals'='הפרטים שלי'; 'This is exactly how people see you in Discover.'='ככה בדיוק רואים אתכם בגילוי.';
  'Replace photo'='החלפת תמונה'; 'Make it the main photo'='להפוך לתמונה הראשית'; 'Pick a question'='בחרו שאלה'; 'Your answer'='התשובה שלכם';
  'Save'='שמירה'; 'Keep it short and specific'='קצר וספציפי';
  'Photos, videos, prompts, voice'='תמונות, סרטונים, שאלות, הקלטה'; 'Your profile always starts with a photo'='הפרופיל תמיד מתחיל בתמונה';
  'Keep at least one photo'='צריך לפחות תמונה אחת'; 'That is the most you can add'='זה המקסימום שאפשר להוסיף'; 
  'Write an answer first'='כתבו קודם תשובה'; 'Record your voice note first'='הקליטו קודם'; 'Photo replaced'='התמונה הוחלפה'; 'Video replaced'='הסרטון הוחלף'
}
$heAdd = ''
foreach ($k in $heE.Keys) { if (-not $doc.Contains('"' + $k + '":')) { $heAdd += '    "' + $k + '": "' + $heE[$k] + '",' + "`n" } }
$doc = $doc.Replace('    "Preferences saved": ', $heAdd + '    "Preferences saved": ')
$hs4 = $doc.IndexOf('</helmet>')
$doc = $doc.Substring(0, $hs4) + [System.IO.File]::ReadAllText("$discScratch\mosaic-style.html", [System.Text.Encoding]::UTF8) + $doc.Substring($hs4)
Write-Output "profile editor added"

# ── 5x. every test profile gets its own mix and order ─────────────────────────
#  Up to 6 photos, 6 prompts, 2 videos and 2 voice notes each, never the same
#  combination twice. Layout tokens: p photo, q prompt, v video, a voice, d details.
$R = [ordered]@{
  Maya    = @{ pics = 6; keep = @(0,1,2,3); extra = @(,@('Green flags I look for','you ask a second question before you tell your own story.'));
               layout = "'q','p','v','q','p','a','q','p','d','p','q','a','q','p'"; vids = @(,@('maya-v1','0:12',12)); voices = @(@('My go-to karaoke song','0:12',12), @('A story I tell too often','0:21',21)) }
  Noa     = @{ pics = 4; keep = @(0,1,2,3); extra = @();
               layout = "'v','q','p','q','a','p','d','v','q','p','q'"; vids = @(@('noa-v1','0:09',9), @('noa-v2','0:16',16)); voices = @(,@('How I sound when I am excited','0:10',10)) }
  Shira   = @{ pics = 5; keep = @(0,1,2); extra = @(@('My most irrational fear','silence in a recording studio. It is never really silent.'), @('I geek out on','the sound of old rooms. Churches, stairwells, empty pools.'), @('Typical Friday night','a small gig, one drink, home before the last song ends.'));
               layout = "'q','p','q','q','p','a','d','p','q','q','p','q'"; vids = @(); voices = @(,@('How I sound when I am excited','0:09',9)) }
  Tamar   = @{ pics = 3; keep = @(1,2); extra = @();
               layout = "'q','v','p','d','q','p'"; vids = @(,@('tamar-v1','0:14',14)); voices = @() }
  Avigail = @{ pics = 6; keep = @(0,1,2); extra = @(,@('Typical Sunday','flour on everything, music too loud, a cake nobody asked for.'));
               layout = "'q','p','v','p','a','q','p','d','v','q','p','a','q','p'"; vids = @(@('avigail-v1','0:11',11), @('avigail-v2','0:07',7)); voices = @(@('A story I tell too often','0:18',18), @('My go-to karaoke song','0:11',11)) }
  Roni    = @{ pics = 2; keep = @(0,1,2); extra = @(@('I geek out on','octopuses. Ask me anything. Please.'), @('Typical Friday night','a swim at sunset, then whoever is cooking.'));
               layout = "'q','v','q','a','q','p','d','q','q'"; vids = @(,@('roni-v1','0:13',13)); voices = @(,@('How I sound when I am excited','0:15',15)) }
  Itai    = @{ pics = 5; keep = @(0,1,2); extra = @();
               layout = "'v','q','p','p','q','d','v','p','q','p'"; vids = @(@('itai-v1','0:08',8), @('itai-v2','0:12',12)); voices = @() }
  Yonatan = @{ pics = 3; keep = @(0,1,2); extra = @(@('My simple pleasure','the first coffee on the balcony while the cats pretend not to want breakfast.'), @('I am looking for','someone who loves a long meal and does not mind a boat that stays in the harbour.'), @('Two truths and a lie','I have taught four hundred teenagers, I sailed to Cyprus, I have never burnt toast.'));
               layout = "'q','a','q','p','q','d','q','p','a','q','q'"; vids = @(); voices = @(@('A story I tell too often','0:24',24), @('My most irrational fear','0:08',8)) }
  Adam    = @{ pics = 4; keep = @(1,3); extra = @();
               layout = "'q','p','v','d','p','a','q','p'"; vids = @(,@('adam-v1','0:15',15)); voices = @(,@('My go-to karaoke song','0:13',13)) }
  Roi     = @{ pics = 6; keep = @(0,1,2,3); extra = @();
               layout = "'p','q','p','p','a','q','d','p','q','p','q'"; vids = @(); voices = @(,@('A story I tell too often','0:19',19)) }
  Eitan   = @{ pics = 2; keep = @(0,1,2); extra = @();
               layout = "'v','q','a','q','d','p','v','a','q'"; vids = @(@('eitan-v1','0:10',10), @('eitan-v2','0:17',17)); voices = @(@('My go-to karaoke song','0:10',10), @('How I sound when I am excited','0:13',13)) }
  Omer    = @{ pics = 4; keep = @(0,1,2); extra = @(@('Typical Friday night','a fire, a small group, and more stars than you expected.'), @('I geek out on','knots. I can teach you nine of them in an hour.'));
               layout = "'q','p','q','v','q','d','p','q','p','q'"; vids = @(,@('omer-v1','0:14',14)); voices = @() }
}
$js = { param($s) "'" + ($s -replace "'", "\'") + "'" }
foreach ($name in $R.Keys) {
  $cfg = $R[$name]
  $pat = "(?s)\{ name:'" + $name + "',.*?\] \},?"
  $m = [regex]::Match($doc, $pat)
  if (-not $m.Success) { throw "roster entry not found: $name" }
  $block = $m.Value
  $low = $name.ToLower()
  $pics = (1..$cfg.pics | ForEach-Object { "'assets/people/$low-$_.jpg'" }) -join ','
  $block = [regex]::Replace($block, "pics:\[[^\]]*\]", "pics:[$pics]")
  $block = [regex]::Replace($block, " n:\d+,", " n:$($cfg.pics),")
  $block = [regex]::Replace($block, "layout:\[[^\]]*\]", "layout:[$($cfg.layout)]")
  $pm = [regex]::Match($block, "prompts:\[(.*\])\] \}")
  $pairs = [regex]::Matches($pm.Groups[1].Value, "\['((?:[^'\\]|\\.)*)','((?:[^'\\]|\\.)*)'\]")
  $list = @()
  foreach ($k in $cfg.keep) { if ($k -lt $pairs.Count) { $list += "['" + $pairs[$k].Groups[1].Value + "','" + $pairs[$k].Groups[2].Value + "']" } }
  foreach ($a in $cfg.extra) { $list += "[" + (& $js $a[0]) + "," + (& $js $a[1]) + "]" }
  $vids = ($cfg.vids | ForEach-Object { "{ src:'assets/people/" + $_[0] + ".jpg', dur:'" + $_[1] + "', secs:" + $_[2] + " }" }) -join ', '
  $voices = ($cfg.voices | ForEach-Object { "{ q:" + (& $js $_[0]) + ", dur:'" + $_[1] + "', secs:" + $_[2] + " }" }) -join ', '
  $tail = if ($block.EndsWith(',')) { ',' } else { '' }
  $block = $block.Substring(0, $pm.Index) + "prompts:[" + ($list -join ',') + "],`n      videos:[" + $vids + "], voices:[" + $voices + "] }" + $tail
  $doc = $doc.Substring(0, $m.Index) + $block + $doc.Substring($m.Index + $m.Length)
  $q = ([regex]::Matches($cfg.layout, "'q'")).Count; $p = ([regex]::Matches($cfg.layout, "'p'")).Count + 1
  $v = ([regex]::Matches($cfg.layout, "'v'")).Count; $a = ([regex]::Matches($cfg.layout, "'a'")).Count
  if ($q -ne $list.Count -or $p -ne $cfg.pics -or $v -ne @($cfg.vids).Count -or $a -ne @($cfg.voices).Count) { throw ("{0}: layout counts p{1} q{2} v{3} a{4} do not match data p{5} q{6} v{7} a{8}" -f $name, $p, $q, $v, $a, $cfg.pics, $list.Count, @($cfg.vids).Count, @($cfg.voices).Count) }
  Write-Output ("{0,-8} photos {1}  prompts {2}  videos {3}  voice {4}" -f $name, $p, $q, $v, $a)
}

# ── 5y. depth pass ────────────────────────────────────────────────────────────
#  Rounder corners, a thin rim of light on every surface, layered shadows and
#  domed buttons. Last in, so it settles the look over everything above.
$hs5 = $doc.IndexOf('</helmet>')
if ($hs5 -lt 0) { throw "helmet close not found for the depth pass" }
$doc = $doc.Substring(0, $hs5) + [System.IO.File]::ReadAllText("$scratch\pop-style.html", [System.Text.Encoding]::UTF8) + $doc.Substring($hs5)
#  the deck grabs the pointer only once a sideways swipe has really started;
#  grabbing it on touch-down sent taps meant for the hearts to the deck instead
$dirLine = "if (this._dir === 'y') { this._sx = null; return; }"
$dn = ([regex]::Matches($doc, [regex]::Escape($dirLine))).Count
if ($dn -ne 1) { throw "expected one swipe-direction line, found $dn" }
$doc = $doc.Replace($dirLine, $dirLine + "`n      try { const cd = this.deck(); if (cd && cd.setPointerCapture && e.pointerId != null) cd.setPointerCapture(e.pointerId); } catch (_) {}")
# ── 5z. a way back from the like sheet ───────────────────────────────────────
#  It only closed by tapping the dim area above it. A header now says where
#  you go: back to the same person's profile, just where you left it.
$lk = $doc.IndexOf('<sc-if value="{{ overlay.like }}">')
if ($lk -lt 0) { throw "like sheet not found" }
$grab = '<div style="width:42px;height:4px;border-radius:999px;background:var(--color-divider);margin:0 auto var(--space-4)"></div>'
$gi = $doc.IndexOf($grab, $lk)
if ($gi -lt 0 -or $gi - $lk -gt 1200) { throw "like sheet handle not found" }
$head = '<div class="lk-head"><span class="lk-grab"></span>' +
  '<button class="lk-x tg-tap" sc-camel-on-click="{{ closeOverlay }}" aria-label="Close"><svg width="15" height="15" sc-camel-view-box="0 0 24 24" fill="none" stroke="#1C2536" stroke-width="2.4" stroke-linecap="round"><path d="M6 6 18 18"></path><path d="M18 6 6 18"></path></svg></button></div>'
$doc = $doc.Substring(0, $gi) + $head + $doc.Substring($gi + $grab.Length)
Swap1 "likeIsPhoto: st.likeTarget === 'photo'," "likeName: person ? person.name : '', likeIsPhoto: st.likeTarget === 'photo'," 'like name'
$lkCss = '<style>.lk-head{position:relative;display:flex;align-items:center;justify-content:flex-end;margin:-4px -4px 12px;min-height:40px}' +
  '.lk-grab{position:absolute;left:50%;top:-6px;width:42px;height:4px;margin-left:-21px;border-radius:999px;background:var(--color-divider)}' +
  '.lk-back{display:inline-flex;align-items:center;gap:4px;height:36px;padding:0 12px 0 6px;border:0;border-radius:999px;cursor:pointer;font:inherit;font-size:14px;color:#1C2536;' +
  'background:linear-gradient(168deg,rgba(255,255,255,.95),rgba(239,237,230,.9));box-shadow:0 1px 2px rgba(28,37,54,.14),0 8px 16px -10px rgba(28,37,54,.5),inset 0 1px 0 #fff}' +
  '.lk-x{width:36px;height:36px;border:0;border-radius:50%;display:grid;place-items:center;cursor:pointer;' +
  'background:linear-gradient(168deg,rgba(255,255,255,.95),rgba(239,237,230,.9));box-shadow:0 1px 2px rgba(28,37,54,.14),0 8px 16px -10px rgba(28,37,54,.5),inset 0 1px 0 #fff}</style>'
$hs6 = $doc.IndexOf('</helmet>')
$doc = $doc.Substring(0, $hs6) + $lkCss + $doc.Substring($hs6)
if (-not $doc.Contains('"Back to":')) { $doc = $doc.Replace('    "Preferences saved": ', '    "Back to": "חזרה אל",' + "`n" + '    "Preferences saved": ') }
# ── 5aa. no cross on Discover: swiping left is how you move on ────────────────
$px = $doc.IndexOf('aria-label="Not for me"')
if ($px -lt 0) { throw "pass button not found" }
$ps0 = $doc.LastIndexOf('<sc-if value="{{ showDock }}"', $px)
$pe0 = $doc.IndexOf('</sc-if>', $px) + '</sc-if>'.Length
if ($ps0 -lt 0 -or $px - $ps0 -gt 900) { throw "pass button block not found" }
$doc = $doc.Substring(0, $ps0) + $doc.Substring($pe0)
$doc = $doc.Replace('Swipe left, or tap the cross, to move on. The heart is how you like.', 'Swipe left to move on. The heart is how you like.')
# ── 5ab. a happier ground ─────────────────────────────────────────────────────
#  The grey stock read as dull for a place people come to find someone. The
#  ground is now a warm cream with a faint blush of light at the top; white
#  cards still sit clearly on it.
$doc = $doc.Replace('#E3E1D8', '#F9F1E9').Replace('#EFEDE6', '#FFF9F3').Replace('#CBC7B9', '#EDE0D5')
$doc = [regex]::Replace($doc, '227, ?225, ?216', '249, 241, 233')
$warm = '<style>[data-tg-phone]{background:radial-gradient(130% 42% at 50% -8%,rgba(240,140,155,.16),transparent 62%),' +
  'radial-gradient(90% 38% at 100% 104%,rgba(255,196,160,.16),transparent 70%),#F9F1E9 !important}</style>'
$hs7 = $doc.IndexOf('</helmet>')
$doc = $doc.Substring(0, $hs7) + $warm + $doc.Substring($hs7)
# ── 5ac. the main photo holds every photo; the heart becomes a swipe ─────────
#  Squares down the right edge of the main photo switch between photos and
#  videos; the blurred ground keeps the first photo. Only prompts, voice notes
#  and details sit under it, in glass tinted by the person's colours. Swiping
#  right likes whatever the frame shows; left still moves on. Tapping a photo
#  no longer opens it full screen. The glass for the remaining hearts matches.
function Once8([string]$from, [string]$to, [string]$what) {
  $i = $script:doc.IndexOf($from)
  if ($i -lt 0) { throw "discover: '$what' not found" }
  $script:doc = $script:doc.Substring(0, $i) + $to + $script:doc.Substring($i + $from.Length)
}
# which photo the main frame shows
Once8 "      const shotK = k => built.shotOf(built.photos[k].src);" ("      const shotK = k => built.shotOf(built.photos[k].src);`n" +
  "      const media = this.personItems(person).filter(i => i.kind === 'photo' || i.kind === 'video');`n" +
  "      const hi = Math.min(st.heroIdx || 0, media.length - 1), cur = media[hi], isVid = cur.kind === 'video';`n" +
  "      const heroThumbs = media.map((m, k) => ({ bg: built.shotOf(m.src), cls: (k === hi ? 'on' : '') + (m.kind === 'video' ? ' vid' : ''), pick: e => { halt(e); this.setState({ heroIdx: k, playing: null }); } }));") 'photo index'
Once8 "bg: shotK(0), open: e => { halt(e); openAt(0); }, like: e => { halt(e); this.openLike('photo', 0); }," "bg: built.shotOf(cur.src), bg0: shotK(0), open: e => { halt(e); if (isVid) this.playMedia(cur); }, like: e => { halt(e); if (isVid) this.openLike('photo', 0, { src: cur.src }); else this.openLike('photo', built.photos.findIndex(p => p.src === cur.src)); }, playCls: isVid && st.playing === cur.id ? 'is-playing' : '', playShow: isVid ? 'flex' : 'none', dur: isVid ? cur.dur : '', secs: isVid ? (cur.secs || 10) + 's' : '0s'," 'hero values'
# the first 'tiles' belongs to Discover; photos leave the area under the main photo
Once8 "blocks: built.blocks, tiles: built.tiles," "blocks: built.blocks, tiles: built.tiles.filter(x => !x.isPhoto && !x.isVideo), heroThumbs, stripShow: media.length > 1 ? 'flex' : 'none'," 'discover tiles'
Once8 "this.setState({ personIdx: this.state.personIdx + 1, viewer: null }" "this.setState({ personIdx: this.state.personIdx + 1, viewer: null, heroIdx: 0 }" 'pass resets the photo'

# the squares, down the right edge of the main photo; the count badge gives way to them
Once8 '<span class="tgd-count">{{ dv.hero.count }}</span>' ('<div class="tgs-strip" style="display:{{ dv.stripShow }}">' +
  '<sc-for list="{{ dv.heroThumbs }}" as="h" hint-placeholder-count="4">' +
  '<button class="tgs-thumb tg-tap {{ h.cls }}" style="background:{{ h.bg }}" sc-camel-on-click="{{ h.pick }}" aria-label="Show this photo"></button>' +
  '</sc-for></div>') 'hero count'
Once8 '<div class="tgd-hero">' '<div class="tgd-hero {{ dv.hero.playCls }}">' 'hero frame'
Once8 '<div class="tgs-strip"' ('<span class="tgs-play" style="display:{{ dv.hero.playShow }}"><svg width="26" height="26" sc-camel-view-box="0 0 24 24" fill="#FBFAF6"><path d="M8 5.5v13l11-6.5z"></path></svg></span><span class="tgs-dur" style="display:{{ dv.hero.playShow }}">{{ dv.hero.dur }}</span><i class="tgs-prog" style="animation-duration:{{ dv.hero.secs }}"></i><div class="tgs-strip"') 'play badge'
# the blurred ground keeps the first photo whatever the frame shows
$doc = $doc.Replace('<div class="tgd-backdrop-img" style="background:{{ dv.hero.bg }}">', '<div class="tgd-backdrop-img" style="background:{{ dv.hero.bg0 }}">')


# swipe right likes whatever the main frame shows; the heart leaves the main photo
Once8 "      const heroThumbs = media.map(" "      this._heroLike = () => { if (isVid) this.openLike('photo', 0, { src: cur.src }); else this.openLike('photo', built.photos.findIndex(p => p.src === cur.src)); };`n      const heroThumbs = media.map(" 'hero like'
$hs80 = $doc.IndexOf('<span class="tgd-heart"><button class="tg-tap" sc-camel-on-click="{{ dv.hero.like }}"')
if ($hs80 -lt 0) { throw 'discover: hero heart not found' }
$he0 = $doc.IndexOf('</span>', $hs80) + 7
$doc = $doc.Substring(0, $hs80) + '<span class="tgs-likecue" data-tg-likecue="1"><svg width="34" height="34" sc-camel-view-box="0 0 24 24" fill="none" stroke="#E4485B" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M20.8 5.6a5.2 5.2 0 0 0-7.4 0L12 7l-1.4-1.4a5.2 5.2 0 1 0-7.4 7.4L12 21.5l8.8-8.5a5.2 5.2 0 0 0 0-7.4z"></path></svg></span>' + $doc.Substring($he0)
$hs81 = $doc.IndexOf('<span class="tgd-heart"><button class="tg-tap" sc-camel-on-click="{{ ep.view.hero.like }}"')
if ($hs81 -ge 0) { $he1 = $doc.IndexOf('</span>', $hs81) + 7; $doc = $doc.Substring(0, $hs81) + $doc.Substring($he1) }
Once8 "    const vx = dx > 0 ? Math.min(28, dx * 0.18) : dx;   // right: a small give, nothing more" "    const vx = dx > 0 ? Math.min(120, dx * 0.8) : dx;" 'right drag'
Once8 "    if (l) l.style.opacity = '0';" "    if (l) l.style.opacity = '0';`n    const c = document.querySelector('[data-tg-likecue]'); if (c) { const k = Math.max(0, Math.min(1, dx / 90)); c.style.opacity = String(k); c.style.transform = 'scale(' + (0.6 + k * 0.4) + ')'; }" 'like cue'
Once8 "    if (dx <= -80) { this.passPerson(); return; }" "    if (dx <= -80) { this.passPerson(); return; }`n    if (dx >= 80 && this._heroLike) { const d0 = this.deck(); if (d0) { d0.style.transition = 'transform .22s ease'; d0.style.transform = 'none'; } this.setStamp(0); this._justDragged = false; this._heroLike(); this._justDragged = true; return; }" 'swipe like'
Once8 'Swipe left to move on. The heart is how you like.' 'Swipe right to like the photo, left to move on.' 'hint'

$css8 = '<style>' +
  '.tgs-strip{position:absolute;bottom:16px;inset-inline-end:12px;z-index:3;flex-direction:column;gap:8px}' +
  '.tgs-thumb{width:46px;height:46px;border-radius:12px;border:2px solid rgba(255,255,255,.55);padding:0;cursor:pointer;' +
  'box-shadow:0 4px 12px rgba(0,0,0,.35);opacity:.78;transition:transform .25s cubic-bezier(.34,1.42,.64,1),opacity .2s ease,filter .2s ease,border-color .2s ease}' +
  '.tgs-thumb:not(.on){opacity:.55;filter:saturate(.6) brightness(.85);border-color:rgba(255,255,255,.35);transform:scale(.9)}' +
  '.tgs-thumb.on{opacity:1;filter:none;border-color:#fff;transform:scale(1.08);box-shadow:0 10px 22px -6px rgba(0,0,0,.6)}' +
  '.tgd-hero-img{transition:background-image .35s ease}' +
  '.tgs-thumb.vid{position:relative}.tgs-thumb.vid::after{content:"";position:absolute;inset:0;border-radius:10px;background:rgba(0,0,0,.28) no-repeat center/14px url("data:image/svg+xml,%3Csvg xmlns=%27http://www.w3.org/2000/svg%27 viewBox=%270 0 24 24%27%3E%3Cpath d=%27M8 5.5v13l11-6.5z%27 fill=%27white%27/%3E%3C/svg%3E")}' +
  '.tgs-play{position:absolute;left:50%;top:42%;width:72px;height:72px;margin:-36px 0 0 -36px;z-index:2;border-radius:50%;align-items:center;justify-content:center;pointer-events:none;' +
  'background:rgba(251,250,246,.22);backdrop-filter:blur(10px);border:1px solid rgba(251,250,246,.55);box-shadow:0 10px 30px rgba(0,0,0,.35);transition:opacity .25s ease,transform .25s ease}' +
  '.tgd-hero.is-playing .tgs-play{opacity:0;transform:scale(.8)}' +
  '.tgs-dur{position:absolute;top:14px;inset-inline-start:14px;z-index:2;height:24px;align-items:center;padding:0 9px;border-radius:999px;font-size:12px;color:#FBFAF6;background:rgba(0,0,0,.4)}' +
  '.tgs-prog{position:absolute;inset-inline-start:0;bottom:0;height:3px;width:0;z-index:3;background:#E4485B}' +
  '.tgd-hero.is-playing .tgs-prog{animation:tgd-prog linear forwards}' +
  '.tgd-hero.is-playing .tgd-hero-img{transform:scale(1.12);transition:transform 12s linear,background-image .35s ease}' +
  '.tgd-root .tgt-card,.tgd-root .tgt-tone .tgt-card,.tgd-root .tgt-voice{background:color-mix(in srgb,var(--pv) 30%,color-mix(in srgb,#FBFAF6 70%,transparent)) !important;' +
  '-webkit-backdrop-filter:blur(16px) saturate(1.3);backdrop-filter:blur(16px) saturate(1.3);border:1px solid rgba(255,255,255,.55) !important}' +
  '.tgd-root .tgt-voice .tgt-vrow{background:transparent}' +
  '.tgd-root .tgt-dtl > span{background:color-mix(in srgb,var(--pv) 30%,color-mix(in srgb,#FBFAF6 70%,transparent)) !important;color:#1C2536 !important;' +
  'border:1px solid rgba(255,255,255,.55) !important;box-shadow:inset 0 1px 0 rgba(255,255,255,.6),0 6px 14px -10px rgba(0,0,0,.45);-webkit-backdrop-filter:blur(14px);backdrop-filter:blur(14px)}' +
  '.tgd-root .tgd-heart{background:transparent !important;box-shadow:0 6px 14px -8px rgba(0,0,0,.45) !important}' +
  '.tgd-root .tgd-heart button,.tgd-root .tgt-heart{overflow:hidden;background:color-mix(in srgb,var(--pv) 30%,color-mix(in srgb,#FBFAF6 70%,transparent)) !important;background-image:none !important;' +
  '-webkit-backdrop-filter:blur(16px) saturate(1.3);backdrop-filter:blur(16px) saturate(1.3);border:1px solid rgba(255,255,255,.55) !important;' +
  'box-shadow:inset 0 1px 0 rgba(255,255,255,.6),0 6px 14px -10px rgba(0,0,0,.45) !important}' +
  '.tgd-root .tgd-heart button svg,.tgd-root .tgt-heart svg{position:relative;z-index:1;stroke:#E4485B;stroke-width:1.5px;filter:none}' +
  '.tgd-root .tgd-heart button:active svg,.tgd-root .tgt-heart:active svg{filter:none;stroke-width:2px}' +
  '.tgs-likecue{position:absolute;left:50%;top:42%;width:84px;height:84px;margin:-42px 0 0 -42px;z-index:3;border-radius:50%;display:flex;align-items:center;justify-content:center;pointer-events:none;opacity:0;transform:scale(.6);transition:opacity .15s ease;' +
  'background:color-mix(in srgb,var(--pv) 30%,color-mix(in srgb,#FBFAF6 70%,transparent));-webkit-backdrop-filter:blur(16px) saturate(1.3);backdrop-filter:blur(16px) saturate(1.3);border:1px solid rgba(255,255,255,.55);box-shadow:inset 0 1px 0 rgba(255,255,255,.6),0 10px 24px -10px rgba(0,0,0,.5)}' +
  '.tgs-strip{gap:7px !important}.tgs-thumb{width:44px !important;height:44px !important}' +
  '</style>'
$hs8 = $doc.IndexOf('</helmet>')
$doc = $doc.Substring(0, $hs8) + $css8 + $doc.Substring($hs8)
# ── 5ad. a slimmer Discover header ────────────────────────────────────────────
#  The title, People/Couples and the sort took a third of the first screen.
#  Less air above, smaller pills, and the sort as a slim row of its own.
$db0 = '<div class="tgd-bar" style="position:sticky;top:0;z-index:2;background:color-mix(in srgb,var(--color-bg) 88%,transparent);backdrop-filter:blur(10px);padding:30px var(--space-4) var(--space-3)">'
if (-not $doc.Contains($db0)) { throw "discover header not found" }
$doc = $doc.Replace($db0, $db0.Replace('class="tgd-bar"', 'class="tgd-bar tgd-slim"'))
$slim = '<style>' +
  '.tgd-slim{padding:18px var(--space-4) 8px !important}' +
  '.tgd-slim > div:first-child{margin-bottom:6px !important}' +
  '.tgd-slim > div:first-child > span{font-size:20px !important}' +
  '.tgd-slim > div:first-child > div{padding:2px !important}' +
  '.tgd-slim > div:first-child button{font-size:12px !important;padding:4px 11px !important}' +
  '.tgd-slim > div:last-child{padding:2px !important}' +
  '.tgd-slim > div:last-child button{font-size:11.5px !important;padding:4px 4px !important}' +
  '</style>'
$hs9 = $doc.IndexOf('</helmet>')
$doc = $doc.Substring(0, $hs9) + $slim + $doc.Substring($hs9)# ── 5ae. Edit profile, the same shape as Discover ────────────────────────────
#  Photos and videos live in the main frame with its column of squares: tap a
#  square to show it, hold one and drag to reorder (the top square is the main
#  photo), tap the frame to edit what it shows. Only prompts and voice notes
#  sit in the cards below. View shows exactly what Discover shows.
$epJs = @"
      const media = items.filter(i => i.kind === 'photo' || i.kind === 'video');
      const ehi = Math.min(st.epIdx || 0, media.length - 1), ecur = media[ehi], eVid = ecur.kind === 'video';
      const MEDIA = he ? { photo: 'תמונה', video: 'סרטון' } : { photo: 'Photo', video: 'Video' };
      const editStrip = media.map((m, k) => ({ id: m.id, bg: shotOf(m.src), aria: MEDIA[m.kind] + ' ' + (k + 1),
        cls: (k === ehi ? 'on' : '') + (m.kind === 'video' ? ' vid' : '') + (st.epFlash === m.id ? ' ep-flash' : ''),
        down: e => this.epDown(e, m.id, () => this.setState({ epIdx: k, playing: null })) }));
      const editMain = { bg: shotOf(ecur.src), bg0: photos[0] ? shotOf(photos[0].src) : 'none', playShow: eVid ? 'flex' : 'none',
        label: ehi === 0 ? (he ? 'התמונה הראשית' : 'Main photo') : MEDIA[ecur.kind] + ' ' + (ehi + 1) + (he ? ' מתוך ' : ' of ') + media.length,
        editLabel: he ? 'עריכה' : 'Edit', edit: () => this.epOpen(ecur.id) };
      const editCards = editTiles.filter(t => t.kind === 'prompt' || t.kind === 'voice').map((t, k) => Object.assign({}, t, { pos: String(k + 1) }));
      const vhi = Math.min(st.epViewIdx || 0, media.length - 1), vcur = media[vhi], vVid = vcur.kind === 'video';
      const viewThumbs = media.map((m, k) => ({ bg: shotOf(m.src), cls: (k === vhi ? 'on' : '') + (m.kind === 'video' ? ' vid' : ''),
        pick: e => { if (e && e.stopPropagation) e.stopPropagation(); this.setState({ epViewIdx: k, playing: null }); } }));
"@
Once8 '      const nm = st.form.name || ' ($epJs + '      const nm = st.form.name || ') 'editor values'
Once8 'list, counters, adds, sheet, vitals, editTiles, editHero,' 'list, counters, adds, sheet, vitals, editTiles, editHero, editStrip, editMain, editCards,' 'editor return'
Once8 "          blocks: built.blocks, tiles: built.tiles,`n          hero: {" ("          blocks: built.blocks, tiles: built.tiles.filter(x => !x.isPhoto && !x.isVideo), heroThumbs: viewThumbs, stripShow: media.length > 1 ? 'flex' : 'none',`n" +
  "          hero: {`n            playCls: vVid && st.playing === vcur.id ? 'is-playing' : '', playShow: vVid ? 'flex' : 'none', dur: vVid ? vcur.dur : '', secs: vVid ? (vcur.secs || 10) + 's' : '0s', bg0: photos[0] ? shotOf(photos[0].src) : 'none',") 'view values'
Once8 "bg: photos[0] ? shotOf(photos[0].src) : 'none', open: () => {}," "bg: shotOf(vcur.src), open: () => { if (vVid) this.playMedia(vcur); }," 'view hero'
Once8 "canFirst: !!cur && sk === 'photo' && items.indexOf(cur) > 0," "canFirst: !!cur && sk === 'photo' && items.filter(i => i.kind === 'photo' || i.kind === 'video').indexOf(cur) > 0," 'make main'
Once8 "hasSize: !!cur && (sk === 'photo' || sk === 'prompt' || sk === 'video') && items.indexOf(cur) > 0," "hasSize: !!cur && sk === 'prompt'," 'sizes'

# View: the squares, as in Discover
$vw = $doc.IndexOf('<div class="ep-view">')
if ($vw -lt 0) { throw "view tab not found" }
$pre = $doc.Substring(0, $vw); $post = $doc.Substring($vw)
$post = $post.Replace('<div class="tgd-backdrop-img" style="background:{{ ep.view.hero.bg }}">', '<div class="tgd-backdrop-img" style="background:{{ ep.view.hero.bg0 }}">')
$vh = $post.IndexOf('<div class="tgd-hero">'); $post = $post.Substring(0, $vh) + '<div class="tgd-hero {{ ep.view.hero.playCls }}">' + $post.Substring($vh + '<div class="tgd-hero">'.Length)
$vc = '<span class="tgd-count">{{ ep.view.hero.count }}</span>'
$vi = $post.IndexOf($vc); if ($vi -lt 0) { throw "view count not found" }
$post = $post.Substring(0, $vi) + '<span class="tgs-play" style="display:{{ ep.view.hero.playShow }}"><svg width="26" height="26" sc-camel-view-box="0 0 24 24" fill="#FBFAF6"><path d="M8 5.5v13l11-6.5z"></path></svg></span><span class="tgs-dur" style="display:{{ ep.view.hero.playShow }}">{{ ep.view.hero.dur }}</span><i class="tgs-prog" style="animation-duration:{{ ep.view.hero.secs }}"></i>' +
  '<div class="tgs-strip" style="display:{{ ep.view.stripShow }}"><sc-for list="{{ ep.view.heroThumbs }}" as="h" hint-placeholder-count="4"><button class="tgs-thumb tg-tap {{ h.cls }}" style="background:{{ h.bg }}" sc-camel-on-click="{{ h.pick }}" aria-label="Show this photo"></button></sc-for></div>' + $post.Substring($vi + $vc.Length)
$doc = $pre + $post

# Edit: the main frame and its squares in place of the old first tile; cards below
$es = $doc.IndexOf('<div class="tgd-backdrop" aria-hidden="true"><div class="tgd-backdrop-img" style="background:{{ ep.editHero.bg }}"></div></div>')
$ee = $doc.IndexOf('<div class="tgm ep-mosaic">', $es)
if ($es -lt 0 -or $ee -lt $es) { throw "edit stage not found ($es, $ee)" }
$doc = $doc.Substring(0, $es) + [System.IO.File]::ReadAllText("$discScratch\editor-main.html", [System.Text.Encoding]::UTF8).TrimEnd() + "`n                    " + $doc.Substring($ee)
Once8 '<sc-for list="{{ ep.editTiles }}" as="t" hint-placeholder-count="7">' '<sc-for list="{{ ep.editCards }}" as="t" hint-placeholder-count="4">' 'edit cards'
Once8 '<div class="tgt {{ t.cls }}" data-ep-id="{{ t.id }}"' '<div class="tgt {{ t.cls }}" data-ep-id="{{ t.id }}" data-ep-grp="t"' 'card group'
Once8 '<span>Tap to edit · Hold and drag to move</span>' '<span>Tap to edit · Hold a square or a card, then drag to move</span>' 'edit hint'

# the drag works within its own group; the main frame always holds a photo
Once8 '  epDown(e, id) {' '  epDown(e, id, tap) {' 'drag tap'
Once8 'this._ep = { id, el, sc,' 'this._ep = { id, tap, el, sc,' 'drag tap state'
Once8 "    const nodes = [...document.querySelectorAll('[data-ep-id]')];" "    const grp = d.el.getAttribute('data-ep-grp'), nodes = [...document.querySelectorAll(grp ? '[data-ep-grp=`"' + grp + '`"]' : '[data-ep-id]')];" 'drag group'
Once8 "    const bad = ti === 0 && kind !== 'photo';" "    const bad = ti === 0 && kind !== 'photo' && d.el.getAttribute('data-ep-grp') === 'm';" 'drag main rule'
Once8 '      if (!d.moved && Date.now() - d.t0 < 320) this.epOpen(d.id);' '      if (!d.moved && Date.now() - d.t0 < 320) { if (d.tap) d.tap(); else this.epOpen(d.id); }' 'tap'
Once8 "    const moved = items.splice(d.di, 1)[0];`n    items.splice(d.ni, 0, moved);`n    if (items[0].kind !== 'photo') { this.toast('Your profile always starts with a photo'); return; }`n    this.setItems(items);`n    this.setState({ epFlash: moved.id });" (
  "    const moved = items.splice(items.findIndex(i => i.id === d.order[d.di]), 1)[0];`n" +
  "    let to = items.findIndex(i => i.id === d.order[d.ni]); if (d.ni > d.di) to++;`n" +
  "    items.splice(to, 0, moved);`n" +
  "    const fm = items.find(i => i.kind === 'photo' || i.kind === 'video');`n" +
  "    if (!fm || fm.kind !== 'photo') { this.toast('Your profile always starts with a photo'); return; }`n" +
  "    this.setItems(items);`n" +
  "    const mk = items.filter(i => i.kind === 'photo' || i.kind === 'video').indexOf(moved);`n" +
  "    this.setState(mk >= 0 ? { epFlash: moved.id, epIdx: mk } : { epFlash: moved.id });") 'reorder by id'
Once8 "    if (items.length && items[0].kind !== 'photo') {`n      const k = items.findIndex(i => i.kind === 'photo');`n      if (k > 0) { const p = items.splice(k, 1)[0]; items.unshift(p); }`n    }" (
  "    const fm = items.findIndex(i => i.kind === 'photo' || i.kind === 'video');`n" +
  "    if (fm >= 0 && items[fm].kind !== 'photo') {`n      const k = items.findIndex(i => i.kind === 'photo');`n      if (k > 0) { const p = items.splice(k, 1)[0]; items.splice(fm, 0, p); }`n    }") 'first is a photo'
Once8 "    items.unshift(items.splice(k, 1)[0]);`n    this.setItems(items);" "    items.unshift(items.splice(k, 1)[0]);`n    this.setItems(items);`n    this.setState({ epIdx: 0 });" 'main resets'
$doc = $doc.Replace("      this.setState({ epFlash: id });`n      return;", "      this.setState({ epFlash: id, epIdx: 99 });`n      return;")

$css9 = '<style>' +
  '.ep-main{margin-bottom:12px}' +
  '.ep-mainlabel{position:absolute;top:14px;inset-inline-start:14px;z-index:3;height:26px;padding:0 11px;border-radius:999px;display:flex;align-items:center;font-size:12px;color:#FBFAF6;background:rgba(0,0,0,.38);-webkit-backdrop-filter:blur(8px);backdrop-filter:blur(8px)}' +
  '.ep-mainedit{position:absolute;bottom:16px;inset-inline-start:14px;z-index:3;height:36px;padding:0 15px;border-radius:999px;display:flex;align-items:center;gap:7px;font-size:13px;cursor:pointer;color:#1C2536;' +
  'background:color-mix(in srgb,var(--pv) 30%,color-mix(in srgb,#FBFAF6 70%,transparent));-webkit-backdrop-filter:blur(16px) saturate(1.3);backdrop-filter:blur(16px) saturate(1.3);border:1px solid rgba(255,255,255,.55);box-shadow:inset 0 1px 0 rgba(255,255,255,.6),0 6px 14px -10px rgba(0,0,0,.45)}' +
  '.ep-strip .tgs-thumb{touch-action:none;-webkit-user-select:none;user-select:none}' +
  '.ep-strip .tgs-thumb.ep-lift{transition:none;opacity:1;filter:none;z-index:6;border-color:#fff;box-shadow:0 16px 30px -6px rgba(0,0,0,.65)}' +
  '.ep-strip .tgs-thumb.ep-target{opacity:1;filter:none;border-color:#fff;box-shadow:0 0 0 3px rgba(255,255,255,.45)}' +
  '.ep-strip .tgs-thumb.ep-target-no{border-style:dashed}' +
  '</style>'
$hs10 = $doc.IndexOf('</helmet>')
$doc = $doc.Substring(0, $hs10) + $css9 + $doc.Substring($hs10)
# ── 6. give the tab bar the hook the new bar layer needs, and make check-in reachable ──
$doc = [regex]::Replace($doc, '(<sc-if value="\{\{ showTabs \}\}">\s*<div )style=', '${1}data-tg-tabs="1" style=')
if ($doc -notmatch 'data-tg-tabs') { throw "tab bar hook not applied" }

$doc = [regex]::Replace($doc, '(>End this connection</button>)',
    '${1}' + "`n                <button class=""btn btn-ghost tg-tap"" style=""font-size:12.5px;margin-top:2px"" sc-camel-on-click=""{{ simulateCheckin }}"">Simulate: three days of silence</button>")
if ($doc -notmatch 'simulateCheckin') { throw "check-in trigger not added" }
$simMatch = "simulateMatch: () => this.setState({ overlay: 'match', matched: true }),"
if ($doc.Contains($simMatch)) {
    $doc = $doc.Replace($simMatch, $simMatch + "`n      simulateCheckin: () => this.setState({ overlay: 'checkin' }),")
}

[System.IO.File]::WriteAllText("$scratch\app-template.rebuilt.dc.html", $doc, $utf8)
Write-Output ("rebuilt template: {0} KB, {1} lines" -f [math]::Round(([System.Text.Encoding]::UTF8.GetByteCount($doc))/1KB,1), ($doc -split "`n").Length)
Write-Output ("otp screen present: {0} | checkin trigger: {1}" -f ($doc -match 'at\.otp'), ($doc -match 'simulateCheckin'))
