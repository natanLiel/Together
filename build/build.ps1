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
  "      const heroThumbs = media.map((m, k) => ({ bg: built.shotOf(m.src), k, p: (k - hi + media.length) % media.length, z: media.length - (k - hi + media.length) % media.length, cls: (k === hi ? 'on' : '') + (m.kind === 'video' ? ' vid' : ''), pick: e => { halt(e); this.setState({ heroIdx: k, playing: null }); } }));") 'photo index'
Once8 "bg: shotK(0), open: e => { halt(e); openAt(0); }, like: e => { halt(e); this.openLike('photo', 0); }," "bg: built.shotOf(cur.src), bg0: shotK(0), open: e => this.sideTap(e, media.length, hi, k => this.setState({ heroIdx: k, playing: null }), () => { if (isVid) this.playMedia(cur); else if (media.length > 1) this.setState({ heroIdx: (hi + 1) % media.length }); }), like: e => { halt(e); if (isVid) this.openLike('photo', 0, { src: cur.src }); else this.openLike('photo', built.photos.findIndex(p => p.src === cur.src)); }, playCls: isVid && st.playing === cur.id ? 'is-playing' : '', playShow: isVid ? 'flex' : 'none', dur: isVid ? cur.dur : '', secs: isVid ? (cur.secs || 10) + 's' : '0s'," 'hero values'
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
        editLabel: he ? 'עריכה' : 'Edit', edit: () => this.epOpen(ecur.id), frameTap: e => this.sideTap(e, media.length, ehi, k => this.setState({ epIdx: k, playing: null }), () => this.epOpen(ecur.id)) };
      const editCards = editTiles.filter(t => t.kind === 'prompt' || t.kind === 'voice').map((t, k) => Object.assign({}, t, { pos: String(k + 1) }));
      const vhi = Math.min(st.epViewIdx || 0, media.length - 1), vcur = media[vhi], vVid = vcur.kind === 'video';
      const viewThumbs = media.map((m, k) => ({ bg: shotOf(m.src), k, p: (k - vhi + media.length) % media.length, z: media.length - (k - vhi + media.length) % media.length, cls: (k === vhi ? 'on' : '') + (m.kind === 'video' ? ' vid' : ''),
        pick: e => { if (e && e.stopPropagation) e.stopPropagation(); this.setState({ epViewIdx: k, playing: null }); } }));
"@
Once8 '      const nm = st.form.name || ' ($epJs + '      const nm = st.form.name || ') 'editor values'
Once8 'list, counters, adds, sheet, vitals, editTiles, editHero,' 'list, counters, adds, sheet, vitals, editTiles, editHero, editStrip, editMain, editCards,' 'editor return'
Once8 "          blocks: built.blocks, tiles: built.tiles,`n          hero: {" ("          blocks: built.blocks, tiles: built.tiles.filter(x => !x.isPhoto && !x.isVideo), heroThumbs: viewThumbs, stripShow: media.length > 1 ? 'flex' : 'none',`n" +
  "          hero: {`n            playCls: vVid && st.playing === vcur.id ? 'is-playing' : '', playShow: vVid ? 'flex' : 'none', dur: vVid ? vcur.dur : '', secs: vVid ? (vcur.secs || 10) + 's' : '0s', bg0: photos[0] ? shotOf(photos[0].src) : 'none',") 'view values'
Once8 "bg: photos[0] ? shotOf(photos[0].src) : 'none', open: () => {}," "bg: shotOf(vcur.src), open: e => this.sideTap(e, media.length, vhi, k => this.setState({ epViewIdx: k, playing: null }), () => { if (vVid) this.playMedia(vcur); else if (media.length > 1) this.setState({ epViewIdx: (vhi + 1) % media.length }); })," 'view hero'
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
# ── 5af. the squares fold into a stack; hold to fan them out and pick ────────
#  On the main photo the squares sit folded, overlapping. A finger on the
#  stack fans it out; sliding picks whatever sits under the finger, and the
#  one it rests on when it lifts stays as the main photo. A quick tap fans it
#  out and leaves it open for a second tap.
$doc = $doc.Replace('<div class="tgs-strip" style="display:{{ dv.stripShow }}">', '<div class="tgs-strip tgs-stack {{ dv.stackCls }}" style="display:{{ dv.stripShow }};--n:{{ dv.stackN }}" sc-camel-on-pointer-down="{{ dv.stackDown }}">')
$doc = $doc.Replace('<div class="tgs-strip" style="display:{{ ep.view.stripShow }}">', '<div class="tgs-strip tgs-stack {{ ep.view.stackCls }}" style="display:{{ ep.view.stripShow }};--n:{{ ep.view.stackN }}" sc-camel-on-pointer-down="{{ ep.view.stackDown }}">')
$doc = $doc.Replace('<button class="tgs-thumb tg-tap {{ h.cls }}" style="background:{{ h.bg }}" sc-camel-on-click="{{ h.pick }}" aria-label="Show this photo"></button>', '<button class="tgs-thumb {{ h.cls }}" style="background:{{ h.bg }};--p:{{ h.p }};--k:{{ h.k }};z-index:{{ h.z }}" aria-label="Show this photo"></button>')
if (-not $doc.Contains('{{ dv.stackDown }}') -or -not $doc.Contains('{{ ep.view.stackDown }}')) { throw "stack markup not applied" }
Once8 "heroThumbs, stripShow: media.length > 1 ? 'flex' : 'none'," "heroThumbs, stripShow: media.length > 1 ? 'flex' : 'none', stackCls: st.stackOpen ? 'open' : '', stackN: String(media.length), stackDown: e => this.stackDown(e, k => this.setState({ heroIdx: k, playing: null }))," 'discover stack'
Once8 "heroThumbs: viewThumbs, stripShow: media.length > 1 ? 'flex' : 'none'," "heroThumbs: viewThumbs, stripShow: media.length > 1 ? 'flex' : 'none', stackCls: st.stackOpen ? 'open' : '', stackN: String(media.length), stackDown: e => this.stackDown(e, k => this.setState({ epViewIdx: k, playing: null }))," 'view stack'
Once8 '  passPerson() {' (@"
  sideTap(e, n, idx, set, center) {
    if (e && e.stopPropagation) e.stopPropagation();
    if (this._justDragged || !e || !e.currentTarget) return;
    const r = e.currentTarget.getBoundingClientRect(), x = (e.clientX - r.left) / r.width;
    if (n > 1 && x < 0.3) set((idx - 1 + n) % n);
    else if (n > 1 && x > 0.7) set((idx + 1) % n);
    else if (center) center();
  }

  stackDown(e, pick) {
    if (e.pointerType === 'mouse' && e.button !== 0) return;
    if (e.stopPropagation) e.stopPropagation();
    const wasOpen = !!this.state.stackOpen, t0 = Date.now();
    if (!wasOpen) this.setState({ stackOpen: true });
    const at = y => {
      let best = -1, bd = Infinity;
      [...document.querySelectorAll('.tgs-stack .tgs-thumb')].forEach((t, k) => { const r = t.getBoundingClientRect(), d = Math.abs(y - (r.top + r.height / 2)); if (d < bd) { bd = d; best = k; } });
      return best;
    };
    let last = -1, moved = false;
    const move = ev => {
      if (Math.abs(ev.clientY - e.clientY) > 6) moved = true;
      if (!moved) return;
      if (ev.cancelable) ev.preventDefault();
      const k = at(ev.clientY); if (k >= 0 && k !== last) { last = k; pick(k); }
    };
    const up = ev => {
      window.removeEventListener('pointermove', move); window.removeEventListener('pointerup', up); window.removeEventListener('pointercancel', up);
      if (!wasOpen && !moved && Date.now() - t0 < 260) {
        // a quick tap leaves the stack fanned out; the next touch anywhere else folds it
        const away = ev2 => { if (!ev2.target.closest || !ev2.target.closest('.tgs-stack')) { window.removeEventListener('pointerdown', away, true); this.setState({ stackOpen: false }); } };
        setTimeout(() => window.addEventListener('pointerdown', away, true), 0);
        return;
      }
      if (ev.type === 'pointerup') { const k = at(ev.clientY); if (k >= 0 && k !== last) pick(k); }
      this.setState({ stackOpen: false });
    };
    window.addEventListener('pointermove', move); window.addEventListener('pointerup', up); window.addEventListener('pointercancel', up);
  }

  passPerson() {
"@) 'stack method'
$doc = $doc.Replace("this.setState({ personIdx: this.state.personIdx + 1, viewer: null, heroIdx: 0 }", "this.setState({ personIdx: this.state.personIdx + 1, viewer: null, heroIdx: 0, stackOpen: false }")
$css10 = '<style>' +
  '.tgs-strip.tgs-stack{gap:0 !important;width:44px;touch-action:none;-webkit-user-select:none;user-select:none;height:calc(44px + (var(--n) - 1) * 9px);transition:height .34s cubic-bezier(.3,1.2,.5,1)}' +
  '.tgs-strip.tgs-stack.open{height:calc(44px + (var(--n) - 1) * 51px)}' +
  '.tgs-strip.tgs-stack .tgs-thumb{position:absolute;top:0;left:0;margin:0;touch-action:none;--s:.9;transform:translateY(calc(var(--p) * 9px)) scale(var(--s));' +
  'transition:transform .4s cubic-bezier(.3,1.2,.5,1),opacity .2s ease,filter .2s ease,border-color .2s ease}' +
  '.tgs-strip.tgs-stack .tgs-thumb.on{--s:1.08}' +
  '.tgs-strip.tgs-stack.open .tgs-thumb{transform:translateY(calc(var(--k) * 51px)) scale(var(--s))}' +
  '.tgs-strip.tgs-stack.open .tgs-thumb.on{--s:1.14;transform:translateY(calc(var(--k) * 51px)) translateX(-4px) scale(var(--s))}' +
  '</style>'
$hs11 = $doc.IndexOf('</helmet>')
$doc = $doc.Substring(0, $hs11) + $css10 + $doc.Substring($hs11)
# ── 5ag. tags, one way for everyone ───────────────────────────────────────────
#  Every profile's tags come from the same set: kids, drinking, smoking, food,
#  pets, rhythm, faith and languages, plus a line in your own words. People
#  pick them in The basics (optional) and any time in Edit profile, from the
#  same picker. Every tag is the same pill with an icon, on the photo or under it.
Once8 '  passPerson() {' ([System.IO.File]::ReadAllText("$discScratch\about.js.txt", [System.Text.Encoding]::UTF8).TrimEnd() + "`n`n  passPerson() {") 'about methods'
Once8 "me: { work: 'Product designer', height: '180 cm', home: 'Tel Aviv'," "me: { about: {}, work: '', height: '', home: ''," 'a blank start'
$abJs = @"
    // ——— about you: the tag picker ———
    const ab = (() => {
      const a = st.me.about || {}, tr = s => he ? (Component.ABOUT_HE[s] || s) : s;
      const cats = Component.ABOUT.map(c => {
        const v = a[c.k], picked = c.multi ? (v || []).length > 0 : !!v;
        const otherOn = !c.multi && !!c.other && !!(a[c.k + '_other'] || (v && c.opts.indexOf(v) < 0));
        let opts = c.opts.map(o => { const on = c.multi ? (v || []).indexOf(o) >= 0 : v === o; return { label: tr(o), cls: on ? 'on' : '', pick: () => this.setAbout(c.k, o) }; });
        if (c.multi) opts = opts.concat((v || []).filter(o => c.opts.indexOf(o) < 0).map(o => ({ label: o, cls: 'on', pick: () => this.setAbout(c.k, o) })));
        else if (c.other) opts.push({ label: he ? 'אחר' : 'Other', cls: otherOn ? 'on' : '', pick: () => this.aboutOther(c.k) });
        const draft = ((st.abIn || {})[c.k]) || '';
        return {
          title: he ? c.he : c.title, icon: c.icon,
          state: picked ? (he ? 'בפרופיל שלך' : 'On your profile') : (c.multi ? (he ? 'אפשר כמה · לא מוצג' : 'Pick any · not shown') : (he ? 'לא מוצג' : 'Not shown')),
          stateCls: picked ? 'on' : '', opts,
          inShow: c.other && (c.multi || otherOn) ? 'flex' : 'none',
          inVal: c.multi ? draft : (otherOn ? (v || '') : ''), inHint: he ? (c.hintHe || '') : (c.hint || ''),
          inSet: e => { const t = e.target.value.slice(0, 15); if (c.multi) this.setState({ abIn: Object.assign({}, this.state.abIn || {}, { [c.k]: t }) }); else this.aboutType(c.k, t); },
          addShow: c.multi ? 'inline-flex' : 'none', addCls: draft.trim() ? '' : 'off', addLabel: he ? 'הוספה' : 'Add', add: () => this.aboutAdd(c.k)
        };
      });
      const mine = this.aboutMine(a), draft = st.abDraft || '', preview = this.aboutTags(a, he);
      return {
        cats, preview, ownIcon: Component.ABOUT_OWN_ICON,
        note: he ? 'הכול רשות. כל קטגוריה שלא בוחרים בה פשוט לא מופיעה בפרופיל.' : 'All optional. Any category you leave unpicked simply does not show on your profile.',
        previewTitle: he ? 'ככה זה ייראה בפרופיל שלך' : 'How it shows on your profile',
        emptyShow: preview.length ? 'none' : 'block', emptyText: he ? 'עדיין אין תגיות. בחרו למטה מה שתרצו שיופיע.' : 'No tags yet. Pick below what you want people to see.',
        ownTitle: he ? 'תגיות משלך' : 'Your own tags', ownHint: he ? 'למשל: רץ בשש בבוקר' : 'Like: Runs at 6am',
        mine: mine.map((t, i) => ({ label: t, aria: (he ? 'הסרת ' : 'Remove ') + t, remove: () => this.removeMine(i) })),
        mineShow: mine.length ? 'flex' : 'none', mineCount: mine.length + (he ? ' מתוך 5 · עד 15 תווים' : ' of 5 · 15 letters each'), mineCls: mine.length ? 'on' : '',
        addShow: mine.length < 5 ? 'flex' : 'none', fullShow: mine.length >= 5 ? 'block' : 'none',
        fullText: he ? 'הגעת לחמש. אפשר להסיר אחת כדי להוסיף אחרת.' : 'That is five. Remove one to add another.',
        draft, addLabel: he ? 'הוספה' : 'Add', addCls: draft.trim() ? '' : 'off',
        setDraft: e => { const v = e.target.value.slice(0, 15); this.setState({ abDraft: v ? v.charAt(0).toUpperCase() + v.slice(1) : v }); },
        add: () => this.addMine(),
        later: !!st.abLater, notLater: !st.abLater,
        skip: () => this.setState({ abLater: true }), resume: () => this.setState({ abLater: false }),
        laterLabel: he ? 'אעשה את זה אחר כך' : 'Do this later', resumeLabel: he ? 'להוסיף עכשיו' : 'Add them now',
        laterText: he ? 'אפשר להוסיף או לשנות תגיות בכל זמן מתוך עריכת הפרופיל.' : 'You can add or change your tags any time from Edit profile.'
      };
    })();
"@
Once8 '    // ——— the profile editor ———' ($abJs + '    // ——— the profile editor ———') 'picker values'
Once8 'noPerson: !person, feed, dv,' 'noPerson: !person, feed, dv, ab,' 'picker binding'
Once8 "tags: person.tags.slice(2).map(t => ({ label: t }))," "tags: this.aboutTags(Component.ABOUT_PEOPLE[key], he)," 'their tags'
Once8 "moreLabel: '', hint: '', detailsLabel: '', tags: []," "moreLabel: '', hint: '', detailsLabel: '', tags: this.aboutTags(me.about, he)," 'my tags shown'
Once8 '      const built = this.buildBlocks(items, {' "      const built = this.buildBlocks(items.some(i => i.kind === 'details') ? items : items.concat([{ id: 'd', kind: 'details' }]), {" 'my details tile'

$tagSvg = '<svg width="14" height="14" sc-camel-view-box="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="__D__"></path></svg>'
$nT = ([regex]::Matches($doc, [regex]::Escape('<span>{{ g.label }}</span>'))).Count
if ($nT -lt 2) { throw "detail tags: found $nT" }
$doc = $doc.Replace('<span>{{ g.label }}</span>', '<span class="tg-tag">' + $tagSvg.Replace('__D__', '{{ g.icon }}') + '{{ g.label }}</span>')
$heroIcons = @{ job = 'M4 8h16v11H4zM9 8V5.5h6V8M4 13h16'; intent = 'M9 7a5 5 0 1 1 0 10a5 5 0 1 1 0-10zM15 7a5 5 0 1 1 0 10a5 5 0 1 1 0-10z'; dist = 'M12 3v18M8.5 6.5L12 3l3.5 3.5M8.5 17.5L12 21l3.5-3.5' }
foreach ($pre in @('dv.hero', 'ep.view.hero')) { foreach ($k in @('job', 'intent', 'dist')) {
  $from = '<span>{{ ' + $pre + '.' + $k + ' }}</span>'
  if (-not $doc.Contains($from)) { throw "hero chip not found: $from" }
  $doc = $doc.Replace($from, '<span class="tg-tag">' + $tagSvg.Replace('__D__', $heroIcons[$k]) + '{{ ' + $pre + '.' + $k + ' }}</span>')
} }

$picker = [System.IO.File]::ReadAllText("$discScratch\about-picker.html", [System.Text.Encoding]::UTF8).TrimEnd()
Once8 '<div class="tgp-label">My vitals</div>' ($picker.Replace('__TITLE__', 'About you').Replace('__LATERBTN__', '') + "`n`n                  " + '<div class="tgp-label">My vitals</div>') 'picker in edit'
$bs2 = $doc.IndexOf('<sc-if value="{{ at.basics }}">')
$bf = $doc.IndexOf('<div style="flex:1;min-height:var(--space-6)"></div>', $bs2)
if ($bs2 -lt 0 -or $bf -lt 0) { throw "basics end not found" }
$laterBtn = '<button type="button" class="tga-later tg-tap" sc-camel-on-click="{{ ab.skip }}">{{ ab.laterLabel }}</button>'
$folded = '<sc-if value="{{ ab.later }}"><div class="tgp-label tga-label"><span>A little more about you</span></div>' +
  '<div class="tgp-card tga-folded"><p>{{ ab.laterText }}</p><button type="button" class="tga-resume tg-tap" sc-camel-on-click="{{ ab.resume }}">{{ ab.resumeLabel }}</button></div></sc-if>'
$doc = $doc.Substring(0, $bf) + $folded + "`n              <sc-if value=""{{ ab.notLater }}"">" + $picker.Replace('__TITLE__', 'A little more about you').Replace('__LATERBTN__', $laterBtn) + "</sc-if>`n`n              " + $doc.Substring($bf)

$css11 = '<style>' +
  '.tg-tag{display:inline-flex !important;align-items:center;gap:6px;height:30px;padding:0 12px 0 10px !important;border-radius:999px !important;font-size:12.5px;line-height:1;white-space:nowrap}' +
  '.tg-tag svg{flex:none;opacity:.8}' +
  '.tgd-chips > .tg-tag{color:#FBFAF6;background:rgba(18,20,28,.28) !important;border:1px solid rgba(255,255,255,.3) !important;-webkit-backdrop-filter:blur(12px) saturate(1.2);backdrop-filter:blur(12px) saturate(1.2);box-shadow:inset 0 1px 0 rgba(255,255,255,.25)}' +
  '.tgd-root .tgt-dtl > .tg-tag{height:30px}' +
  '.ep-stage{clip-path:inset(0)}' +
  '.tga{padding:2px 14px 12px}' +
  '.tga-label{display:flex;align-items:center;justify-content:space-between;gap:10px}' +
  '.tga-later{border:0;background:none;padding:4px 0;font:inherit;font-size:12.5px;letter-spacing:0;text-transform:none;color:#E4485B;cursor:pointer}' +
  '.tga-folded{padding:14px 16px;display:flex;flex-direction:column;gap:10px}.tga-folded p{margin:0;font-size:13.5px;line-height:1.45;color:#1C2536}' +
  '.tga-resume{align-self:flex-start;height:34px;padding:0 14px;border-radius:999px;border:1px solid #E4485B;background:#FBF1F0;color:#1C2536;font:inherit;font-size:13px;cursor:pointer}' +
  '.tga-preview{margin:0 0 12px;padding:12px 14px;border-radius:3px;border:1px dashed rgba(28,37,54,.18);background:color-mix(in srgb,#FBFAF6 60%,transparent)}' +
  '.tga-ptitle{font-size:11.5px;letter-spacing:.08em;text-transform:uppercase;color:var(--color-accent-800);margin-bottom:9px}' +
  '.tga-ptags{display:flex;flex-wrap:wrap;gap:6px}' +
  '.tga-ptags .tg-tag{color:#1C2536;background:#FBFAF6;border:1px solid rgba(28,37,54,.12)}' +
  '.tga-empty{margin:0;font-size:13px;line-height:1.45;color:color-mix(in srgb,var(--color-text) 60%,transparent)}' +
  '.tga-state{color:color-mix(in srgb,var(--color-text) 45%,transparent)}.tga-state.on{color:#E4485B}' +
  '.tga-mine{display:inline-flex;align-items:center;gap:7px}.tga-mine svg{opacity:.55}' +
  '.tga-addrow{gap:8px;align-items:center}.tga-addrow .tga-own{margin:0;flex:1}' +
  '.tga-add{display:inline-flex;align-items:center;justify-content:center;flex:none;height:34px;padding:0 15px;border-radius:999px;border:0;background:#1C2536;color:#FBFAF6;font:inherit;font-size:13px;cursor:pointer}.tga-add.off{opacity:.3}' +
  '.tga-cat .tga-catin{margin:10px 0 6px}' +
  '.tga-full{margin:2px 0 6px;font-size:12.5px;color:color-mix(in srgb,var(--color-text) 55%,transparent)}' +
  '.tga-note{font-size:13px;line-height:1.45;color:color-mix(in srgb,var(--color-text) 60%,transparent);margin:-2px 2px 10px}' +
  '.tga-cat{padding:13px 0 5px;border-top:1px solid rgba(28,37,54,.07)}.tga-cat:first-child{border-top:0}' +
  '.tga-head{display:flex;align-items:center;gap:7px;font-size:13.5px;color:#1C2536;margin-bottom:9px}' +
  '.tga-head small{margin-inline-start:auto;font-size:11.5px;color:color-mix(in srgb,var(--color-text) 50%,transparent)}' +
  '.tga-opts{display:flex;flex-wrap:wrap;gap:7px}' +
  '.tga-opt{height:32px;padding:0 13px;border-radius:999px;border:1px solid rgba(28,37,54,.13);background:#FBFAF6;color:#1C2536;font-size:13px;cursor:pointer;transition:background .2s ease,border-color .2s ease,box-shadow .2s ease}' +
  '.tga-opt.on{background:#FBF1F0;border-color:#E4485B;box-shadow:inset 0 0 0 1px #E4485B}' +
  '.tga-own{display:block;width:100%;box-sizing:border-box;height:34px;border-radius:999px;border:1px solid rgba(28,37,54,.11);background:rgba(251,250,246,.7);padding:0 13px;font:inherit;font-size:13px;color:#1C2536;margin-bottom:6px}' +
  '.tga-own::placeholder{color:rgba(28,37,54,.38)}.tga-own:focus{outline:none;border-color:rgba(228,72,91,.55);background:#FBFAF6}' +
  '</style>'
$hs12 = $doc.IndexOf('</helmet>')
$doc = $doc.Substring(0, $hs12) + $css11 + $doc.Substring($hs12)
# ── 5ah. the vitals are part of setting up ───────────────────────────────────
#  The basics now asks for work, home and height too, the same values My
#  vitals shows and edits. Home is needed; work and height are optional and
#  their chips stay off the profile until filled. Age comes from the birthday.
$vitJs = @"
    // ——— the vitals, asked in The basics and shown in My vitals ———
    const vit = (() => {
      const me = st.me, capV = v => v ? v.charAt(0).toUpperCase() + v.slice(1) : v;
      const setMe = patch => this.setState({ me: Object.assign({}, this.state.me, patch) });
      const cm = parseInt(me.height, 10);
      const step = d => { const base = isNaN(cm) ? 170 : cm + d; setMe({ height: Math.max(140, Math.min(215, base)) + ' cm' }); };
      return {
        work: me.work || '', home: me.home || '', heightLabel: me.height || (he ? 'לא נבחר' : 'Not set'), heightCls: me.height ? 'on' : '',
        note: he ? 'מגורים מופיעים כעיר שלך. עבודה וגובה הם רשות.' : 'Home shows as your city. Work and height are optional.',
        setWork: e => setMe({ work: capV(e.target.value.slice(0, 40)) }),
        setHome: e => setMe({ home: capV(e.target.value.slice(0, 30)) }),
        down: () => step(-1), up: () => step(1),
        clear: () => setMe({ height: '' }), clearShow: me.height ? 'inline-flex' : 'none', clearLabel: he ? 'ניקוי' : 'Clear'
      };
    })();

"@
Once8 '    // ——— about you: the tag picker ———' ($vitJs + '    // ——— about you: the tag picker ———') 'vitals values'
Once8 'noPerson: !person, feed, dv, ab,' 'noPerson: !person, feed, dv, ab, vit,' 'vitals binding'
Once8 "    const missing = ['name','last','handle','gender','seeking','intent'].filter(k => !st.form[k]);" "    const missing = ['name','last','handle','gender','seeking','intent'].filter(k => !st.form[k]).concat(st.me.home && st.me.home.trim() ? [] : ['home']);" 'home needed'
Once8 "intent:'מה אתם מחפשים'}[m])" "intent:'מה אתם מחפשים',home:'מגורים'}[m])" 'home hint he'
Once8 "intent:'what you are here for'}[m])" "intent:'what you are here for',home:'home'}[m])" 'home hint'
Once8 "        [he ? 'גובה' : 'Height', me.height]," "        [he ? 'גובה' : 'Height', me.height || (he ? 'לא נבחר' : 'Not set')]," 'height not set'
Once8 "        [he ? 'גיל' : 'Age', '31']," "        [he ? 'גיל' : 'Age', String(age)]," 'age from birthday'
Once8 "name: nm + ', 31', verified: false, city: me.home," "name: nm + ', ' + age, verified: false, city: '', home: me.home, homeShow: me.home ? '' : 'none'," 'age on the profile'
Once8 "job: me.work, intent: cap(st.form.intent || 'A relationship'), dist: me.height," "job: me.work, intent: cap(st.form.intent || ''), dist: me.height, jobShow: me.work ? '' : 'none', distShow: me.height ? '' : 'none', intentShow: st.form.intent ? '' : 'none'," 'empty chips'
$doc = [regex]::Replace($doc, '<span class="tg-tag">(<svg(?:(?!</svg>).)*</svg>)\{\{ ep\.view\.hero\.(job|dist) \}\}</span>', '<span class="tg-tag" style="display:{{ ep.view.hero.$2Show }}">$1{{ ep.view.hero.$2 }}</span>')
$doc = [regex]::Replace($doc, '<span class="tg-tag">(<svg(?:(?!</svg>).)*</svg>)\{\{ ep\.view\.hero\.intent \}\}</span>', '<span class="tg-tag" style="display:{{ ep.view.hero.intentShow }}">$1{{ ep.view.hero.intent }}</span>')
if (-not $doc.Contains('{{ ep.view.hero.jobShow }}')) { throw "empty chip hiding not applied" }
$bs3 = $doc.IndexOf('<sc-if value="{{ at.basics }}">')
$bt = $doc.IndexOf('<div class="tgp-label">I am</div>', $bs3)
if ($bs3 -lt 0 -or $bt -lt 0) { throw "basics 'I am' section not found" }
$doc = $doc.Substring(0, $bt) + [System.IO.File]::ReadAllText("$discScratch\vitals-basics.html", [System.Text.Encoding]::UTF8).TrimEnd() + "`n`n              " + $doc.Substring($bt)
$css12 = '<style>' +
  '.tg-tag[style*="display:none"],.tg-tag[style*="display: none"]{display:none !important}' +
  '.tgv-hrow{display:flex;align-items:center;gap:10px;margin-top:12px;padding-top:12px;border-top:1px solid rgba(28,37,54,.07)}' +
  '.tgv-hlabel{font-size:13px;color:color-mix(in srgb,var(--color-text) 65%,transparent)}' +
  '.tgv-height{display:flex;align-items:center;gap:6px;margin-inline-start:auto}' +
  '.tgv-height b{min-width:64px;text-align:center;font-weight:400;font-size:16px;color:color-mix(in srgb,var(--color-text) 45%,transparent)}.tgv-height b.on{color:#1C2536}' +
  '.tgv-step{width:32px;height:32px;border-radius:50%;border:1px solid rgba(28,37,54,.14);background:#FBFAF6;color:#1C2536;display:grid;place-items:center;cursor:pointer}' +
  '.tgv-clear{border:0;background:none;font:inherit;font-size:12.5px;color:#E4485B;cursor:pointer;padding:4px 2px}' +
  '</style>'
$hs13 = $doc.IndexOf('</helmet>')
$doc = $doc.Substring(0, $hs13) + $css12 + $doc.Substring($hs13)
# ── 5ai. work, home and height are tags, shown only when filled ──────────────
#  On the photo the tags run work, home, height, then what they are here for.
#  Anything left empty has no tag. Home leaves the line under the name, which
#  now only carries the distance.
Once8 "city: person.city + ' · ' + person.dist + ' km away'," "city: person.dist + (he ? ' ק״מ ממך' : ' km away'), home: person.city," 'their home'
Once8 "        [he ? 'מחפש' : 'Looking for', st.form.intent || 'A relationship']" "        [he ? 'מחפש' : 'Looking for', st.form.intent || (he ? 'לא נבחר' : 'Not set')]" 'looking for not set'
Once8 "        [he ? 'עבודה' : 'Work', me.work]," "        [he ? 'עבודה' : 'Work', me.work || (he ? 'לא נבחר' : 'Not set')]," 'work not set'
Once8 "        [he ? 'מגורים' : 'Home', me.home]," "        [he ? 'מגורים' : 'Home', me.home || (he ? 'לא נבחר' : 'Not set')]," 'home not set'
$pin = 'M12 21s-6-5.4-6-10.5a6 6 0 0 1 12 0C18 15.6 12 21 12 21zM12 8.2a2.3 2.3 0 1 1 0 4.6a2.3 2.3 0 1 1 0-4.6z'
foreach ($pre in @('dv.hero', 'ep.view.hero')) {
  $rx = '(<div class="tgd-chips">\s*)(<span class="tg-tag"[^>]*>(?:(?!</span>).)*\{\{ ' + [regex]::Escape($pre) + '\.job \}\}</span>)(\s*)(<span class="tg-tag"[^>]*>(?:(?!</span>).)*\{\{ ' + [regex]::Escape($pre) + '\.intent \}\}</span>)(\s*)(<span class="tg-tag"[^>]*>(?:(?!</span>).)*\{\{ ' + [regex]::Escape($pre) + '\.dist \}\}</span>)'
  $m9 = [regex]::Match($doc, $rx)
  if (-not $m9.Success) { throw "chips not found for $pre" }
  $show = if ($pre -eq 'ep.view.hero') { ' style="display:{{ ' + $pre + '.homeShow }}"' } else { '' }
  $homeTag = '<span class="tg-tag"' + $show + '><svg width="14" height="14" sc-camel-view-box="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="' + $pin + '"></path></svg>{{ ' + $pre + '.home }}</span>'
  $new = $m9.Groups[1].Value + $m9.Groups[2].Value + $m9.Groups[3].Value + $homeTag + $m9.Groups[3].Value + $m9.Groups[6].Value + $m9.Groups[3].Value + $m9.Groups[4].Value
  $doc = $doc.Substring(0, $m9.Index) + $new + $doc.Substring($m9.Index + $m9.Length)
}
$hs14 = $doc.IndexOf('</helmet>')
$doc = $doc.Substring(0, $hs14) + '<style>.tgd-meta:empty,.tgd-meta:has(> .sc-interp:only-child:empty){display:none}</style>' + $doc.Substring($hs14)
# ── 5aj. the handle is optional, and it is for social media ──────────────────
#  The old "name tag" was a required, app-unique name. It is now an optional
#  social media handle, so it no longer blocks Continue or checks if taken.
Once8 "const missing = ['name','last','handle','gender','seeking','intent']" "const missing = ['name','last','gender','seeking','intent']" 'handle optional'
Once8 "const handleTaken = st.form.handle === 'daniel' || st.form.handle === 'admin';" "const handleTaken = false;" 'no taken check'
Once8 "handleNote: !st.form.handle ? 'Your tag is how people mention you in chat.' : handleTaken ? 'That tag is taken. Try another.' : 'together.app/@' + st.form.handle + ' is free.'," "handleNote: ''," 'handle note'
$bs4 = $doc.IndexOf('<sc-if value="{{ at.basics }}">')
$nt = $doc.IndexOf('<span>Name tag</span>', $bs4)
if ($nt -lt 0) { throw "name tag label not found" }
$doc = $doc.Substring(0, $nt) + '<span>Social handle · optional</span>' + $doc.Substring($nt + '<span>Name tag</span>'.Length)
Once8 '    "Name tag": "תג שם",' ('    "Name tag": "תג שם",' + "`n" + '    "Social handle · optional": "שם ברשתות · רשות",') 'handle label he'
# ── 5ak. The basics, condensed ───────────────────────────────────────────────
#  Shorter fields and wheel, less air between sections and inside cards,
#  shorter notes. The wheel's row height lives in its logic too.
Once8 '      const i = Math.round(el.scrollTop / 44);' '      const i = Math.round(el.scrollTop / 36);' 'wheel rows'
Once8 '      const target = idx[el.dataset.wheel] * 44;' '      const target = idx[el.dataset.wheel] * 36;' 'wheel placement'
$doc = $doc.Replace('Scroll each column. Your age shows on your profile, never the date.', 'Only your age shows, never the date.')
$css15 = '<style>' +
  '.tgb .tgp-label{margin:18px 2px 7px !important}' +
  '.tgb .tgb-card{padding:12px !important;gap:10px !important}' +
  '.tgb .tgb-field{gap:4px !important}.tgb .tgb-field > span{font-size:11.5px}' +
  '.tgb .tgb-field small:empty,.tgb .tgb-field small:has(> .sc-interp:only-child:empty){display:none}' +
  '.tgb .tgb-field input.tg-vinput,.tgb .tgb-tag{height:40px !important;min-height:0 !important;font-size:15px !important}.tgb .tgb-tag input{font-size:15px !important}' +
  '.tgb .tg-wheel{height:108px !important;padding:36px 0 !important}.tgb .tg-wheel > div{height:36px !important;font-size:15px !important}' +
  '.tgb .tgb-sel{top:36px !important;height:36px !important}' +
  '.tgb .tgb-note{margin-top:6px !important}' +
  '.tgb .tgv-hrow{margin-top:2px !important;padding-top:8px !important}.tgb .tgv-step{width:30px !important;height:30px !important}' +
  '.tgb .tgb-gender .tgp-tile{padding:12px 8px 10px !important}' +
  '</style>'
$hs15 = $doc.IndexOf('</helmet>')
$doc = $doc.Substring(0, $hs15) + $css15 + $doc.Substring($hs15)
# ── 5al. the birthday wheel: day and month loop, years reach back 90 ─────────
#  Day and month are drawn as nine copies of their list; the wheel reads the
#  value modulo the list and, once it settles near either end, slips back to
#  the middle copy without a jump, so it scrolls forever. Years start 90
#  years back so the oldest person can be 80 and over.
Once8 '    for (let d = 1; d <= daysIn; d++) dayOpts.push(wheelOpt(d, d === st.form.bd));' '    for (let c = 0; c < 9; c++) for (let d = 1; d <= daysIn; d++) dayOpts.push(wheelOpt(d, d === st.form.bd));' 'day loop'
Once8 '    MONTHS.forEach((m, i) => monthOpts.push(wheelOpt(m, i === st.form.bm)));' '    for (let c = 0; c < 9; c++) MONTHS.forEach((m, i) => monthOpts.push(wheelOpt(m, i === st.form.bm)));' 'month loop'
Once8 '    for (let y = 1966; y <= today.getFullYear() - 18; y++)' '    for (let y = today.getFullYear() - 90; y <= today.getFullYear() - 18; y++)' 'years back 90'
Once8 'dayOpts, monthOpts, yearOpts,' 'dayOpts, monthOpts, yearOpts, dayLen: String(daysIn),' 'day length'
Once8 '<div class="tg-wheel {{ dayLitCls }}" data-wheel="d"' '<div class="tg-wheel {{ dayLitCls }}" data-wheel="d" data-len="{{ dayLen }}"' 'day wheel length'
Once8 '<div class="tg-wheel {{ monthLitCls }}" data-wheel="m"' '<div class="tg-wheel {{ monthLitCls }}" data-wheel="m" data-len="12"' 'month wheel length'
Once8 "bYear: e => this.wheel(e, 'by', 1966)," "bYear: e => this.wheel(e, 'by', new Date().getFullYear() - 90)," 'year base'
Once8 "      const i = Math.round(el.scrollTop / 36);`n      const v = base + i;" ("      const i = Math.round(el.scrollTop / 36), len = +el.dataset.len || 0;`n" +
  "      const v = base + (len ? i % len : i);`n" +
  "      if (len && (i < len * 2 || i >= len * 7)) { el.__initUntil = Date.now() + 300; el.scrollTop = (len * 4 + i % len) * 36; }") 'wheel reads the loop'
Once8 "    const idx = { d: this.state.form.bd - 1, m: this.state.form.bm, y: this.state.form.by - 1966 };" "    const f = this.state.form;" 'wheel places'
Once8 "      if (el.dataset.init === '1') return;" ("      if (el.dataset.init === '1' && el.dataset.placed === (el.dataset.len || '')) return;`n" +
  "      el.dataset.placed = el.dataset.len || '';`n" +
  "      const len = +el.dataset.len || 0, w = el.dataset.wheel;`n" +
  "      const at = w === 'd' ? len * 4 + Math.min(f.bd, len) - 1 : w === 'm' ? 48 + f.bm : f.by - (new Date().getFullYear() - 90);") 'wheel place per list'
Once8 "      const target = idx[el.dataset.wheel] * 36;" "      const target = at * 36;" 'wheel target'
# ── 5am. connections you can see and move between ─────────────────────────────
#  A match becomes a connection: one on the free plan, three with Premium.
#  Together lists them with any open slots; Discover carries a banner while
#  you are connected; the chat has a switcher once there is more than one.
#  Everything that named Maya now names whoever the chat is with.
Once8 '  passPerson() {' ([System.IO.File]::ReadAllText("$discScratch\conns.js.txt", [System.Text.Encoding]::UTF8).TrimEnd() + "`n`n  passPerson() {") 'connection methods'
Once8 '    const person = pool[st.personIdx] || null;' ('    const person = pool[st.personIdx] || null;' + "`n" + [System.IO.File]::ReadAllText("$discScratch\conn-vals.js.txt", [System.Text.Encoding]::UTF8).TrimEnd()) 'connection values'
Once8 'noPerson: !person, feed, dv, ab, vit,' 'noPerson: !person, feed, dv, ab, vit, mate, tg, cb, csw, chatBack,' 'connection bindings'
Once8 "    const pool = Component.PEOPLE.filter(p => (p.g === 'w' && wantW) || (p.g === 'm' && wantM));" "    const pool = Component.PEOPLE.filter(p => ((p.g === 'w' && wantW) || (p.g === 'm' && wantM)) && !(st.conns || []).some(c => c.key === p.name.toLowerCase()));" 'connected people leave Discover'
Once8 "sendLike: () => this.setState({ overlay: 'sent', sentKind: 'like' })," "sendLike: () => this.setState({ overlay: 'sent', sentKind: 'like', likedName: person ? person.name : st.likedName })," 'who was liked'
Once8 "this.setState({ overlay: 'sent', sentKind: 'ring', rings: st.rings - 1 });" "this.setState({ overlay: 'sent', sentKind: 'ring', rings: st.rings - 1, likedName: person ? person.name : st.likedName });" 'who was rung'
Once8 "simulateMatch: () => this.setState({ overlay: 'match', matched: true })," "simulateMatch: () => this.matchWith(st.likedName || (person && person.name))," 'a match is a connection'
Once8 "enterChat: () => this.setState({ overlay: null, screen: 'chat', tab: 'together', ended: false })," "enterChat: () => this.setState({ overlay: null, screen: 'chat', tab: 'together', ended: false, conns: (st.conns || []).map((c, i) => i === ci ? Object.assign({}, c, { open: true }) : c) })," 'chat opens'
Once8 "hasConnection: st.matched && !st.ended, noConnection: !st.matched || st.ended," "hasConnection: conns.length > 0, noConnection: conns.length === 0," 'connected'
Once8 "slotLabel: prem ? (st.matched && !st.ended ? '1 of 3 slots' : '0 of 3 slots') : (st.matched && !st.ended ? 'Your one slot is taken' : 'Your one slot is free')," "slotLabel: conns.length + (he ? ' מתוך ' : ' of ') + slots + (he ? ' מקומות' : (slots === 1 ? ' slot' : ' slots'))," 'slot count'
Once8 "quickExit: () => this.setState({ overlay: 'freed', ended: true, matched: false, undoLeft: 0 })," "quickExit: () => this.setState(Object.assign({ overlay: 'freed', undoLeft: 0 }, this.dropPatch()))," 'end now'
Once8 "finishEnd: () => this.setState({ overlay: 'freed', ended: true, matched: false, undoLeft: 0 })," "finishEnd: () => this.setState(Object.assign({ overlay: 'freed', undoLeft: 0 }, this.dropPatch()))," 'end'
Once8 "if (p.undoLeft === 0) { p.overlay = 'freed'; p.ended = true; }" "if (p.undoLeft === 0) { p.overlay = 'freed'; Object.assign(p, this.dropPatch()); }" 'end after the hour'
Once8 "    if (this.state.matched && !this.state.ended) { this.setState({ overlay: 'upgrade', upgradeCtx: 'slots' }); return; }" "    if ((this.state.conns || []).length >= this.slotCount()) { if (this.isPrem()) this.toast('All three slots are taken'); else this.setState({ overlay: 'upgrade', upgradeCtx: 'slots' }); return; }" 'likes wait for a slot'
# the name in the ritual and its notes
Once8 "matchName: 'Maya'," "matchName: mate.name," 'match name'
Once8 "'Send these to Maya'" "'Send these to ' + mate.name" 'send picks'
Once8 "this.toast('Maya has been notified')" "this.toast(mate.name + ' has been notified')" 'notified'
Once8 "'Maya asked you · '" "mate.name + ' asked you · '" 'asked you'
Once8 "t: 'Your three are with Maya'" "t: 'Your three are with ' + mate.name" 'three are with'
Once8 "'Chat opens the moment Maya has answered yours." "'Chat opens the moment ' + mate.name + ' has answered yours." 'chat opens when'

$bits = [System.IO.File]::ReadAllText("$discScratch\conn-bits.html", [System.Text.Encoding]::UTF8)
$banner = $bits.Substring($bits.IndexOf('<!--BANNER-->') + 13, $bits.IndexOf('<!--SWITCH-->') - $bits.IndexOf('<!--BANNER-->') - 13).Trim()
$switch = $bits.Substring($bits.IndexOf('<!--SWITCH-->') + 13).Trim()
# Discover: the banner takes the place of the old slot-full note
$sf = $doc.IndexOf('<sc-if value="{{ slotFull }}">')
$sfe = $doc.IndexOf('</sc-if>', $sf) + 8
if ($sf -lt 0) { throw "slot-full note not found" }
$doc = $doc.Substring(0, $sf) + $banner + $doc.Substring($sfe)
# Together: the list of connections and open slots
$tgs = $doc.IndexOf('<sc-if value="{{ at.together }}">')
$hc = $doc.IndexOf('<sc-if value="{{ hasConnection }}">', $tgs)
$hce = $doc.IndexOf('</sc-if>', $hc) + 8
if ($tgs -lt 0 -or $hc -lt 0) { throw "together card not found" }
$doc = $doc.Substring(0, $hc) + [System.IO.File]::ReadAllText("$discScratch\together-list.html", [System.Text.Encoding]::UTF8).Trim() + $doc.Substring($hce)
$ip = $doc.IndexOf('<sc-if value="{{ isPremium }}">', $tgs)
$ipe = $doc.IndexOf('</sc-if>', $ip) + 8
if ($ip -gt 0 -and $ip - $tgs -lt 8000) { $doc = $doc.Substring(0, $ip) + $doc.Substring($ipe) }
# chat: back goes to Together, the switcher sits under the header, the face and name follow the chat
$cs = $doc.IndexOf('<sc-if value="{{ at.chat }}">')
$bk = $doc.IndexOf('sc-camel-on-click="{{ go.discover }}" aria-label="Back"', $cs)
if ($bk -lt 0 -or $bk - $cs -gt 3000) { throw "chat back not found" }
$doc = $doc.Substring(0, $bk) + 'sc-camel-on-click="{{ chatBack }}" aria-label="Back"' + $doc.Substring($bk + 'sc-camel-on-click="{{ go.discover }}" aria-label="Back"'.Length)
$cb2 = $doc.IndexOf('<div style="padding:var(--space-3) var(--space-4) 0">', $cs)
if ($cb2 -lt 0) { throw "chat body not found" }
$doc = $doc.Substring(0, $cb2) + $switch + "`n`n              " + $doc.Substring($cb2)
foreach ($scr in @('at.chat', 'at.waiting', 'at.videocall')) {
  $s0 = $doc.IndexOf('<sc-if value="{{ ' + $scr + ' }}">')
  $p0 = $doc.IndexOf('url(assets/people/maya-1.jpg)', $s0)
  if ($s0 -lt 0 -or $p0 -lt 0 -or $p0 - $s0 -gt 4000) { throw "photo in $scr not found" }
  $doc = $doc.Substring(0, $p0) + 'url({{ mate.photo }})' + $doc.Substring($p0 + 'url(assets/people/maya-1.jpg)'.Length)
}
# every other Maya in the screens from Together to the overlays
$r0 = $doc.IndexOf('<sc-if value="{{ at.together }}">'); $r1 = $doc.IndexOf('data-tg-caption', $r0); if ($r1 -lt 0) { throw 'caption not found' }
$mid = $doc.Substring($r0, $r1 - $r0).Replace('>Maya<', '>{{ mate.name }}<').Replace('Maya', '{{ mate.name }}')
$mid = $mid.Replace('>You two connected<', '>You and {{ mate.name }} connected<').Replace('You pick three questions for her. She picks three for you.', 'You pick three questions for {{ mate.name }}, and they pick three for you.')
$doc = $doc.Substring(0, $r0) + $mid + $doc.Substring($r1)

$css16 = '<style>' +
  '.tgc-list{display:flex;flex-direction:column;gap:10px;margin-top:4px}' +
  '.tgc-card{display:flex;align-items:center;gap:14px;width:100%;padding:12px 14px;border-radius:16px;border:1px solid rgba(255,255,255,.75);background:rgba(251,250,246,.8);-webkit-backdrop-filter:blur(14px);backdrop-filter:blur(14px);box-shadow:inset 0 1px 0 rgba(255,255,255,.85),0 12px 26px -18px rgba(28,37,54,.5);text-align:start;font:inherit;color:#1C2536;cursor:pointer}' +
  '.tgc-face{position:relative;width:56px;height:56px;border-radius:50%;flex:none;box-shadow:0 0 0 2px #FBFAF6,0 6px 14px -6px rgba(0,0,0,.4)}' +
  '.tgc-face i{position:absolute;top:1px;inset-inline-end:1px;width:12px;height:12px;border-radius:50%;background:#E4485B;box-shadow:0 0 0 2px #FBFAF6}' +
  '.tgc-txt{flex:1;min-width:0;display:flex;flex-direction:column;gap:3px}' +
  '.tgc-txt b{font-family:var(--font-heading) !important;font-weight:400;font-size:19px;line-height:1.15}' +
  '.tgc-txt small{font-size:13px;color:var(--color-accent-800);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.tgc-txt small.turn{color:#E4485B}' +
  '.tgc-empty{background:transparent;border:1.5px dashed rgba(28,37,54,.18);box-shadow:none;-webkit-backdrop-filter:none;backdrop-filter:none}' +
  '.tgc-empty .tgc-txt b{font-size:16px;color:rgba(28,37,54,.7)}' +
  '.tgc-plus{display:grid;place-items:center;background:rgba(28,37,54,.05);box-shadow:none;color:rgba(28,37,54,.45)}' +
  '.tgc-upsell{margin-top:14px;border:0;background:none;color:#E4485B;font:inherit;font-size:13.5px;cursor:pointer;width:100%;justify-content:center}' +
  '.tgc-banner{position:absolute;top:8px;inset-inline:16px;display:flex;align-items:center;gap:12px;width:calc(100% - 32px);margin:0;padding:10px 10px 10px 12px;border-radius:16px;border:1px solid rgba(255,255,255,.55);background:color-mix(in srgb,var(--pv) 30%,color-mix(in srgb,#FBFAF6 70%,transparent));-webkit-backdrop-filter:blur(16px) saturate(1.3);backdrop-filter:blur(16px) saturate(1.3);box-shadow:inset 0 1px 0 rgba(255,255,255,.6),0 10px 22px -14px rgba(0,0,0,.45);font:inherit;color:#1C2536;text-align:start;cursor:pointer}' +
  '.tgc-faces{display:flex;flex:none}.tgc-faces i{width:38px;height:38px;border-radius:50%;box-shadow:0 0 0 2px #FBFAF6}.tgc-faces i + i{margin-inline-start:-14px}' +
  '.tgc-banner .tgc-txt b{font-size:15.5px}.tgc-banner .tgc-txt small{font-size:12px}' +
  '.tgc-open{flex:none;height:32px;padding:0 13px;border-radius:999px;background:#1C2536;color:#FBFAF6;font-size:12.5px;display:inline-flex;align-items:center}' +
  '.tgc-switch{gap:8px;padding:6px 16px 6px;overflow-x:auto;scrollbar-width:none}.tgc-switch::-webkit-scrollbar{display:none}' +
  '.tgc-sw{display:flex;align-items:center;gap:8px;height:40px;padding:0 14px 0 4px;border-radius:999px;border:1px solid rgba(28,37,54,.1);background:rgba(251,250,246,.6);font:inherit;font-size:14px;color:rgba(28,37,54,.62);cursor:pointer;flex:none;position:relative;transition:background .2s ease,color .2s ease,box-shadow .2s ease,transform .2s ease}' +
  '.tgc-sw i{width:32px;height:32px;border-radius:50%;flex:none;opacity:.7;transition:opacity .2s ease}' +
  '.tgc-sw.on{background:#FBFAF6;color:#1C2536;border-color:rgba(28,37,54,.16);box-shadow:0 8px 18px -10px rgba(28,37,54,.5);transform:translateY(-1px)}.tgc-sw.on i{opacity:1}' +
  '.tgc-sw b{position:absolute;top:3px;inset-inline-start:28px;width:10px;height:10px;border-radius:50%;background:#E4485B;box-shadow:0 0 0 2px #FBFAF6}' +
  '</style>'
$hs16 = $doc.IndexOf('</helmet>')
$doc = $doc.Substring(0, $hs16) + $css16 + $doc.Substring($hs16)
# ── 5an. text on the plum panels reads ───────────────────────────────────────
#  The headers on the plum cards and the upgrade sheet were set in the dark
#  ink, which all but disappeared. They take the panel's own cream instead.
$plum = @(
  '<h3 style="font-size:24px;margin:0;color:#1C2536">Three slots instead of one</h3>',
  '<h3 style="font-size:26px;margin:0;color:#1C2536">Premium, 88 NIS a month</h3>',
  '<h3 style="font-size:24px;margin:0;color:#1C2536">{{ priceMonthly }}</h3>',
  '<h3 style="font-size:28px;margin:0 0 8px;color:#1C2536">{{ upTitle }}</h3>',
  '<button class="btn btn-icon tg-tap" style="width:54px;height:54px;background:var(--tg-deep);color:#1C2536"'
)
foreach ($p in $plum) {
  if (-not $doc.Contains($p)) { throw "plum text not found: $p" }
  $doc = $doc.Replace($p, $p.Replace('color:#1C2536', 'color:var(--tg-deep-ink)'))
}
# ── 5ao. the people who liked you ────────────────────────────────────────────
#  With Premium, a like opens that person's whole profile, with whatever they
#  wrote alongside it. Liking back is the match, so the three questions start.
#  Not for me takes them off the list for good.
Once8 '  passPerson() {' ([System.IO.File]::ReadAllText("$discScratch\like-methods.js.txt", [System.Text.Encoding]::UTF8).TrimEnd() + "`n`n  passPerson() {") 'like methods'
$oldRows = "    const likeRows = [`n" +
  "      { name: 'Maya, 28', what: 'Liked your prompt', bg: 'center/cover no-repeat url(assets/people/maya-1.jpg)' },`n" +
  "      { name: 'Shira, 26', what: 'Liked your first photo', bg: 'center/cover no-repeat url(assets/people/shira-1.jpg)' },`n" +
  "      { name: 'Noa, 31', what: 'Liked your Saturday answer', bg: 'center/cover no-repeat url(assets/people/noa-1.jpg)' }`n" +
  "    ];`n"
if (-not $doc.Contains($oldRows)) { throw "old like rows not found" }
$doc = $doc.Replace($oldRows, '')
Once8 '    // ——— about you: the tag picker ———' ([System.IO.File]::ReadAllText("$discScratch\like-vals.js.txt", [System.Text.Encoding]::UTF8).TrimEnd() + "`n`n    // ——— about you: the tag picker ———") 'like values'
Once8 "'settings','help','subscription'].forEach" "'settings','help','subscription','likeprofile'].forEach" 'the screen exists'
Once8 'noPerson: !person, feed, dv, ab, vit, mate, tg, cb, csw, chatBack,' 'noPerson: !person, feed, dv, ab, vit, mate, tg, cb, csw, chatBack, lv,' 'like bindings'
Once8 'likeCount: prem ? 23 : 3, likeRows,' 'likeCount: prem ? likes.length : 3, likeRows,' 'how many liked you'
Once8 "notif: { likes: true," "likes: [{ key: 'maya', what: 'Liked your prompt', note: 'Your Saturday answer made me laugh on the bus.', ring: true }, { key: 'shira', what: 'Liked your first photo', note: '' }, { key: 'noa', what: 'Liked your karaoke note', note: 'Which song? I need to know before I like you back.' }], likeOpen: null, lvIdx: 0,`n    notif: { likes: true," 'who liked you'

# the Likes list: rows open the profile, and the hard-coded ring row goes
$lk = $doc.IndexOf('<sc-if value="{{ at.likes }}">')
$pr = $doc.IndexOf('<sc-if value="{{ isPremium }}">', $lk)
$je = $doc.IndexOf('<sc-for list="{{ likeRows }}" as="row"', $pr)
if ($lk -lt 0 -or $pr -lt 0 -or $je -lt 0) { throw "likes list not found" }
$open = $doc.IndexOf('<div style="display:flex;flex-direction:column;gap:var(--space-2)">', $pr)
$doc = $doc.Substring(0, $open + '<div style="display:flex;flex-direction:column;gap:var(--space-2)">'.Length) + "`n                  " + $doc.Substring($je)
$rowNew = '<sc-for list="{{ likeRows }}" as="row" hint-placeholder-count="3">' + "`n                    " +
  '<button type="button" class="card elev-sm tg-tap tg-row lk-row {{ row.cls }}" style="flex-direction:row;align-items:center;gap:var(--space-3);padding:var(--space-2) var(--space-3);width:100%;text-align:start;font:inherit;color:inherit;cursor:pointer" sc-camel-on-click="{{ row.go }}">' +
  '<span class="washed" style="width:56px;height:56px;border-radius:999px;flex:none;background:{{ row.bg }}"></span>' +
  '<span style="flex:1;min-width:0"><span style="display:block;font-family:var(--font-heading);font-size:17px">{{ row.name }}</span><span style="display:block;font-size:13px;color:var(--color-accent-800);overflow:hidden;text-overflow:ellipsis;white-space:nowrap">{{ row.what }}</span></span>' +
  '<span class="tag tag-accent lk-ringtag" style="display:{{ row.ring }}">Ring</span>' +
  '<svg width="18" height="18" sc-camel-view-box="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="flex:none;opacity:.4"><path d="M9 6l6 6-6 6"></path></svg>' +
  '</button>' + "`n                  " + '</sc-for>'
$lk2 = $doc.IndexOf('<sc-if value="{{ at.likes }}">'); $pr2 = $doc.IndexOf('<sc-if value="{{ isPremium }}">', $lk2)
$je = $doc.IndexOf('<sc-for list="{{ likeRows }}" as="row"', $pr2)
if ($je -lt 0) { throw "premium like loop not found" }
$fe2 = $doc.IndexOf('</sc-for>', $je)
if ($fe2 -lt 0) { throw "like row loop end not found" }
$doc = $doc.Substring(0, $je) + $rowNew + $doc.Substring($fe2 + '</sc-for>'.Length)

# their profile, built from the Discover one so the two always match
$hs20 = $doc.IndexOf('<div class="tgd-hero {{ dv.hero.playCls }}">')
$he20 = $doc.IndexOf('<div style="text-align:center;padding:var(--space-4) 0 0;', $hs20)
if ($hs20 -lt 0 -or $he20 -lt $hs20) { throw "discover profile bounds not found" }
$region = $doc.Substring($hs20, $he20 - $hs20)
$region = $region.Replace('dv.', 'lv.')
$hh = $region.IndexOf('>') + 1
$region = $region.Substring(0, $hh) + '<div class="lv-note" style="display:{{ lv.noteShow }}"><p>{{ lv.note }}</p></div>' + $region.Substring($hh)
$lvScreen = '<sc-if value="{{ at.likeprofile }}">' + "`n" +
  '            <div class="tgd-root lv" style="--pv:{{ lv.pal.v }};--pd:{{ lv.pal.d }};--pl:{{ lv.pal.l }};animation:tg-in .3s ease">' + "`n" +
  '              <div class="tgd-backdrop" aria-hidden="true"><div class="tgd-backdrop-img" style="background:{{ lv.hero.bg0 }}"></div></div>' + "`n" +
  '              <div class="ep-bar"><button class="btn btn-icon tg-tap" sc-camel-on-click="{{ lv.close }}" aria-label="Back"><svg width="19" height="19" sc-camel-view-box="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M15 5l-7 7 7 7"></path></svg></button><span class="ep-title">{{ lv.title }}</span><span style="width:38px"></span></div>' + "`n" +
  '              <div style="padding:0 var(--space-4) 8px"><div data-tg-deck="1" style="display:flex;flex-direction:column;gap:14px;touch-action:pan-y;user-select:none;-webkit-user-select:none;-webkit-user-drag:none" ondragstart="return false" sc-camel-on-pointer-down="{{ deckDown }}" sc-camel-on-pointer-move="{{ deckMove }}" sc-camel-on-pointer-up="{{ deckUp }}" sc-camel-on-pointer-cancel="{{ deckUp }}">' + "`n              " + $region + '</div></div>' + "`n" +
  '              <div class="lv-acts">' +
  '<button type="button" class="lv-drop tg-tap" sc-camel-on-click="{{ lv.drop }}">{{ lv.dropLabel }}</button>' +
  '<button type="button" class="lv-back tg-tap" sc-camel-on-click="{{ lv.likeBack }}"><svg width="17" height="17" sc-camel-view-box="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M20.8 5.6a5.2 5.2 0 0 0-7.4 0L12 7l-1.4-1.4a5.2 5.2 0 1 0-7.4 7.4L12 21.5l8.8-8.5a5.2 5.2 0 0 0 0-7.4z"></path></svg>{{ lv.backLabel }}</button>' +
  '</div>' + "`n" +
  '            </div>' + "`n          </sc-if>" + "`n`n          "
$lkEnd = $doc.IndexOf('<sc-if value="{{ at.together }}">')
if ($lkEnd -lt 0) { throw "together screen not found" }
$doc = $doc.Substring(0, $lkEnd) + $lvScreen + $doc.Substring($lkEnd)

$css17 = '<style>' +
  '.lv{padding-bottom:96px}' +
  '.lv-note{position:absolute;top:14px;inset-inline:14px;z-index:3;margin:0;padding:11px 15px;border-radius:18px;pointer-events:none;' +
  'background:color-mix(in srgb,var(--pv) 30%,color-mix(in srgb,#FBFAF6 70%,transparent));-webkit-backdrop-filter:blur(16px) saturate(1.3);backdrop-filter:blur(16px) saturate(1.3);' +
  'border:1px solid rgba(255,255,255,.55);box-shadow:inset 0 1px 0 rgba(255,255,255,.6),0 14px 30px -14px rgba(0,0,0,.6)}' +
  '.lv-note p{color:#1C2536 !important}' +
  '.lv-note p{margin:0;font-family:var(--font-heading);font-size:16px;line-height:1.35;text-wrap:pretty;display:-webkit-box;-webkit-line-clamp:3;-webkit-box-orient:vertical;overflow:hidden}' +
  '.lv .ep-bar{padding:14px 12px 14px !important}' +
  '.lv-acts{position:sticky;bottom:0;z-index:5;display:flex;gap:10px;padding:12px 16px calc(12px + env(safe-area-inset-bottom));margin-top:14px;' +
  'background:linear-gradient(180deg,color-mix(in srgb,#FBFAF6 0%,transparent),color-mix(in srgb,#FFFCF8 88%,transparent) 42%)}' +
  '.lv-drop,.lv-back{flex:1;height:50px;border-radius:999px;font:inherit;font-size:15px;cursor:pointer;display:inline-flex;align-items:center;justify-content:center;gap:8px}' +
  '.lv-drop{border:1px solid rgba(28,37,54,.16);background:rgba(251,250,246,.8);color:#1C2536}' +
  '.lv-back{border:0;background:#E4485B;color:#FBFAF6;box-shadow:0 12px 24px -12px rgba(228,72,91,.9)}' +
  '.lk-row .lk-ringtag{margin-inline-start:auto}' +
  '.lk-row.lk-ring{border:1.5px solid var(--color-accent-400)}' +
  '</style>'
$hs21 = $doc.IndexOf('</helmet>')
$doc = $doc.Substring(0, $hs21) + $css17 + $doc.Substring($hs21)
# ── 5ap. Discover in one row, and a taller photo ─────────────────────────────
#  The title, the sort and the people/couples switch share a single row; the
#  switch is two small icons. The main photo grows to fill nearly the screen.
$bs5 = $doc.IndexOf('<div class="tgd-bar tgd-slim"')
$be5 = $doc.IndexOf('<button type="button" class="tgc-banner', $bs5)
if ($bs5 -lt 0 -or $be5 -lt $bs5) { throw "discover header bounds not found" }
$sortBtn = { param($v, $s, $c, $set, $label) '<button class="tgd-sortb tg-tap tg-cased" style="background:{{ ' + $v + ' }};box-shadow:{{ ' + $s + ' }};color:{{ ' + $c + ' }}" sc-camel-on-click="{{ ' + $set + ' }}">' + $label + '</button>' }
$head = '<div class="tgd-bar tgd-one" style="position:sticky;top:0;z-index:2;background:color-mix(in srgb,var(--color-bg) 88%,transparent);backdrop-filter:blur(10px);padding:8px var(--space-4) 6px">' + "`n" +
  '                <div class="tgd-onerow">' + "`n" +
  '                  <span class="tgd-title">Discover</span>' + "`n" +
  '                  <div class="tgd-sort">' + "`n                    " +
  (& $sortBtn 'sortA' 'sortAShadow' 'sortAc' 'setSort.recommended' 'For you') + "`n                    " +
  (& $sortBtn 'sortB' 'sortBShadow' 'sortBc' 'setSort.nearby' 'Nearby') + "`n                    " +
  (& $sortBtn 'sortC' 'sortCShadow' 'sortCc' 'setSort.curated' 'Curated') + "`n" +
  '                  </div>' + "`n" +
  '                  <div class="tgd-mode">' + "`n" +
  '                    <button class="tgd-modeb tg-tap" style="background:{{ segSingle }};box-shadow:{{ segSingleShadow }};color:{{ segSingleC }}" sc-camel-on-click="{{ setMode.single }}" aria-label="People"><svg width="17" height="17" sc-camel-view-box="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="8" r="3.6"></circle><path d="M5 20c0-3.6 3.1-5.6 7-5.6s7 2 7 5.6"></path></svg></button>' + "`n" +
  '                    <button class="tgd-modeb tg-tap" style="background:{{ segCouple }};box-shadow:{{ segCoupleShadow }};color:{{ segCoupleC }}" sc-camel-on-click="{{ setMode.couples }}" aria-label="Couples"><svg width="19" height="19" sc-camel-view-box="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><circle cx="8.5" cy="8" r="3.1"></circle><circle cx="16" cy="9" r="2.6"></circle><path d="M2.5 20c0-3.2 2.7-5 6-5s6 1.8 6 5"></path><path d="M15 15.2c2.8.2 4.6 1.9 4.6 4.8"></path></svg></button>' + "`n" +
  '                  </div>' + "`n" +
  '                </div>' + "`n" +
  '              </div>' + "`n`n              "
$doc = $doc.Substring(0, $bs5) + $head + $doc.Substring($be5)
$css18 = '<style>' +
  '.tgd-one .tgd-onerow{position:relative;display:flex;align-items:center;gap:10px;padding:0 !important;padding-inline-end:56px !important;margin:0 !important}' +
  '.tgd-title{font-family:var(--font-heading);font-size:19px;flex:none}' +
  '.tgd-sort{flex:1;min-width:0;display:flex;align-items:center;justify-content:flex-end;gap:0}' +
  '.tgd-sortb{position:relative;flex:0 1 auto;min-width:0;border:0;cursor:pointer;text-align:center;font-size:11.5px;line-height:1;height:26px;padding:0 11px;border-radius:999px;white-space:nowrap;display:inline-flex;align-items:center;justify-content:center}' +
  '.tgd-sortb + .tgd-sortb::before{content:"";position:absolute;inset-inline-start:0;top:7px;bottom:7px;width:1px;background:rgba(28,37,54,.16)}' +
  '.tgd-mode{position:absolute;top:50%;transform:translateY(-50%);inset-inline-end:0;flex:none;display:flex;align-items:center;gap:1px}' +
  '.tgd-modeb{width:25px;height:22px;border:0;border-radius:999px;cursor:pointer;display:grid;place-items:center;padding:0;box-shadow:none !important}' +
  '.tgd-modeb svg{width:14px;height:14px}' +
  '.tgd-root .tgd-hero-img{aspect-ratio:3/4.8}' +
  '</style>'
$hs22 = $doc.IndexOf('</helmet>')
$doc = $doc.Substring(0, $hs22) + $css18 + $doc.Substring($hs22)
# ── 5aq. their profile swipes too ────────────────────────────────────────────
#  On the profile of someone who liked you, the same gestures apply: right
#  likes them back, left takes them off the list.
Once8 "    if (dx <= -80) { this.passPerson(); return; }" "    if (dx <= -80) { if (this.state.screen === 'likeprofile') { this.dropLike(); return; } this.passPerson(); return; }" 'left on their profile'
Once8 "    if (dx >= 80 && this._heroLike) {" ("    if (dx >= 80 && this.state.screen === 'likeprofile') { const dl = this.deck(); if (dl) { dl.style.transition = 'transform .22s ease'; dl.style.transform = 'none'; } this.setStamp(0); this.likeBack(); return; }`n" + "    if (dx >= 80 && this._heroLike) {") 'right on their profile'
# ── 5ar. the connection banner slides away ───────────────────────────────────
#  Holding the banner and dragging it up dismisses it, the way a phone
#  notification goes. Leaving Discover and coming back brings it back.
Once8 '  passPerson() {' (@"
  // hold the banner and push it up to dismiss it
  cbDown(e) {
    if (e.pointerType === 'mouse' && e.button !== 0) return;
    const el = e.currentTarget;
    this._cb = { el, y0: e.clientY, y: e.clientY, moved: false };
    if (!this._cbMove) { this._cbMove = ev => this.cbMove(ev); this._cbUp = ev => this.cbUp(ev); }
    window.addEventListener('pointermove', this._cbMove);
    window.addEventListener('pointerup', this._cbUp);
    window.addEventListener('pointercancel', this._cbUp);
  }
  cbMove(ev) {
    const d = this._cb;
    if (!d) return;
    const dy = Math.min(0, ev.clientY - d.y0);
    if (Math.abs(ev.clientY - d.y0) > 6) d.moved = true;
    if (!d.moved) return;
    if (ev.cancelable) ev.preventDefault();
    d.y = ev.clientY;
    d.el.style.transition = 'none';
    d.el.style.transform = 'translateY(' + dy + 'px)';
    d.el.style.opacity = String(Math.max(0, 1 + dy / 90));
  }
  cbUp() {
    const d = this._cb;
    window.removeEventListener('pointermove', this._cbMove);
    window.removeEventListener('pointerup', this._cbUp);
    window.removeEventListener('pointercancel', this._cbUp);
    this._cb = null;
    if (!d) return;
    const dy = d.y - d.y0;
    if (d.moved) { this._cbDragged = true; setTimeout(() => { this._cbDragged = false; }, 280); }
    if (dy <= -40) {
      d.el.style.transition = 'transform .22s ease, opacity .22s ease';
      d.el.style.transform = 'translateY(-120%)';
      d.el.style.opacity = '0';
      setTimeout(() => { this.setState({ cbHide: true }); d.el.style.cssText = d.el.style.cssText.replace(/transform[^;]*;?|opacity[^;]*;?|transition[^;]*;?/g, ''); }, 200);
      return;
    }
    d.el.style.transition = 'transform .24s cubic-bezier(.34,1.42,.64,1), opacity .2s ease';
    d.el.style.transform = 'none';
    d.el.style.opacity = '1';
  }

  passPerson() {
"@) 'banner drag'
Once8 "      show: conns.length ? 'flex' : 'none'," "      show: conns.length && !st.cbHide ? 'flex' : 'none', down: e => this.cbDown(e)," 'banner hidden'
Once8 "      go: () => conns.length === 1 ? this.switchChat(0) : this.tabTo('together')" "      go: () => { if (this._cbDragged) return; if (conns.length === 1) this.switchChat(0); else this.tabTo('together'); }" 'banner tap'
Once8 '  tabTo(tab) { this.setState({ tab, screen: tab, overlay: null }); }' "  tabTo(tab) { this.setState({ tab, screen: tab, overlay: null, cbHide: false }); }" 'coming back shows it again'
Once8 '  nav(screen, extra) { this.setState(Object.assign({ screen, overlay: null }, extra || {})); }' "  nav(screen, extra) { this.setState(Object.assign({ screen, overlay: null }, screen === 'discover' ? { cbHide: false } : {}, extra || {})); }" 'and by any other way in'
$doc = $doc.Replace('<button type="button" class="tgc-banner tg-tap" style="display:{{ cb.show }}" sc-camel-on-click="{{ cb.go }}">', '<button type="button" class="tgc-banner tg-tap" style="display:{{ cb.show }}" sc-camel-on-click="{{ cb.go }}" sc-camel-on-pointer-down="{{ cb.down }}">')
if (-not $doc.Contains('{{ cb.down }}')) { throw "banner drag not wired" }
$hs23 = $doc.IndexOf('</helmet>')
$doc = $doc.Substring(0, $hs23) + '<style>.tgc-banner{touch-action:pan-x;-webkit-user-select:none;user-select:none;will-change:transform}</style>' + $doc.Substring($hs23)
# ── 5as. the question bank ───────────────────────────────────────────────────
#  Twelve rounds of questions, each with its own mark and a line saying what
#  it is for. The picker shows the mark on the chip and the line underneath.
$qs0 = $doc.IndexOf('  static QCATS = [')
$qe0 = $doc.IndexOf("`n  ];", $qs0) + "`n  ];".Length
if ($qs0 -lt 0 -or $qe0 -lt $qs0) { throw "question bank not found" }
$doc = $doc.Substring(0, $qs0) + [System.IO.File]::ReadAllText("$discScratch\qcats.js.txt", [System.Text.Encoding]::UTF8).TrimEnd() + $doc.Substring($qe0)
Once8 'qCats: cats.map((c, i) => ({' "qCatSub: (cats[st.qCat] || cats[0]).sub, qCats: cats.map((c, i) => ({ icon: c.icon," 'the mark and the line'
Once8 'sc-camel-on-click="{{ c.pick }}">{{ c.name }}</button>' 'sc-camel-on-click="{{ c.pick }}"><span style="margin-inline-end:5px">{{ c.icon }}</span>{{ c.name }}</button>' 'the mark on the chip'
$qc0 = $doc.IndexOf('<sc-for list="{{ qCats }}" as="c"')
$qcEnd = $doc.IndexOf('</div>', $doc.IndexOf('</sc-for>', $qc0)) + '</div>'.Length
if ($qc0 -lt 0 -or $qcEnd -lt $qc0) { throw "category row not found" }
$doc = $doc.Substring(0, $qcEnd) + "`n              " + '<p class="qcat-sub">{{ qCatSub }}</p>' + $doc.Substring($qcEnd)
$hs24 = $doc.IndexOf('</helmet>')
$doc = $doc.Substring(0, $hs24) + '<style>.qcat-sub{margin:-6px 2px 12px;font-size:12.5px;line-height:1.4;color:color-mix(in srgb,var(--color-text) 58%,transparent)}</style>' + $doc.Substring($hs24)
# ── 5at. moving between the rounds, and a banner that floats ─────────────────
#  The round chips stay at the top while the questions scroll, the chosen one
#  slides into view, and a sideways swipe on the list moves a round along.
#  On Discover the connection banner lies over the photo instead of pushing it.
Once8 'qCatSub: (cats[st.qCat] || cats[0]).sub, qCats: cats.map((c, i) => ({ icon: c.icon,' "qCatSub: (cats[st.qCat] || cats[0]).sub, qCatStep: d => this.qStep(d), qCats: cats.map((c, i) => ({ icon: c.icon, cls: i === st.qCat ? 'on' : ''," 'round moves'
Once8 '<button class="tag tg-tap" style="flex:none;border:0;cursor:pointer;white-space:nowrap;background:{{ c.bg }};color:{{ c.fg }}"' '<button class="tag tg-tap qcat {{ c.cls }}" style="flex:none;border:0;cursor:pointer;white-space:nowrap;background:{{ c.bg }};color:{{ c.fg }}"' 'mark the chosen round'
Once8 '  passPerson() {' (@"
  // the rounds: keep the chosen chip in view, and let a sideways drag move along
  qStep(d) {
    const n = Component.QCATS.length;
    this.setState({ qCat: ((this.state.qCat || 0) + d + n) % n });
  }
  qSync() {
    if (this.state.screen !== 'pickq') return;
    const on = document.querySelector('.qcat.on');
    if (!on || on === this._qLast) return;
    this._qLast = on;
    try { on.scrollIntoView({ block: 'nearest', inline: 'center', behavior: 'smooth' }); } catch (_) { }
  }
  qDown(e) {
    if (e.pointerType === 'mouse' && e.button !== 0) return;
    this._q = { x: e.clientX, y: e.clientY, dir: null };
    if (!this._qMove) { this._qMove = ev => this.qMove(ev); this._qUp = () => this.qUp(); }
    window.addEventListener('pointermove', this._qMove);
    window.addEventListener('pointerup', this._qUp);
    window.addEventListener('pointercancel', this._qUp);
  }
  qMove(ev) {
    const d = this._q;
    if (!d) return;
    const dx = ev.clientX - d.x, dy = ev.clientY - d.y;
    if (d.dir === null) {
      if (Math.abs(dx) < 14 && Math.abs(dy) < 14) return;
      d.dir = Math.abs(dx) > Math.abs(dy) * 1.4 ? 'x' : 'y';
    }
    if (d.dir !== 'x' || d.done) return;
    if (ev.cancelable) ev.preventDefault();
    if (Math.abs(dx) > 60) { d.done = true; this.qStep(dx < 0 ? 1 : -1); }
  }
  qUp() {
    window.removeEventListener('pointermove', this._qMove);
    window.removeEventListener('pointerup', this._qUp);
    window.removeEventListener('pointercancel', this._qUp);
    this._q = null;
  }

  passPerson() {
"@) 'round navigation'
Once8 '  componentDidUpdate() { this.applyLang(); this.applyAccent(); this.applyWheels(); }' '  componentDidUpdate() { this.applyLang(); this.applyAccent(); this.applyWheels(); this.qSync(); }' 'keep the chip in view'
$qrow = $doc.IndexOf('<div style="display:flex;gap:6px;overflow-x:auto;padding-bottom:4px;margin-bottom:var(--space-3)">')
if ($qrow -lt 0) { throw "round row not found" }
$doc = $doc.Substring(0, $qrow) + '<div class="qcat-row" style="display:flex;gap:6px;overflow-x:auto;padding-bottom:4px;margin-bottom:var(--space-3)">' + $doc.Substring($qrow + '<div style="display:flex;gap:6px;overflow-x:auto;padding-bottom:4px;margin-bottom:var(--space-3)">'.Length)
$qlist = $doc.IndexOf('<sc-for list="{{ qOptions }}" as="q"')
$qlistOpen = $doc.LastIndexOf('<div style="display:flex;flex-direction:column;gap:8px">', $qlist)
if ($qlistOpen -lt 0) { throw "question list not found" }
$doc = $doc.Substring(0, $qlistOpen) + '<div class="qcat-list" style="display:flex;flex-direction:column;gap:8px" sc-camel-on-pointer-down="{{ qDown }}">' + $doc.Substring($qlistOpen + '<div style="display:flex;flex-direction:column;gap:8px">'.Length)
Once8 'noPerson: !person, feed, dv, ab, vit, mate, tg, cb, csw, chatBack, lv,' 'noPerson: !person, feed, dv, ab, vit, mate, tg, cb, csw, chatBack, lv, qDown: e => this.qDown(e),' 'the drag binding'
# the banner floats over the photo
$css19 = '<style>' +
  '.tgd-root{position:relative}' +
  '.tgc-banner{position:absolute !important;top:8px !important;inset-inline:16px !important;margin:0 !important;z-index:6 !important}' +
  '.qcat-row{position:sticky;top:0;z-index:4;scroll-snap-type:x proximity;scrollbar-width:none;padding-top:6px;background:linear-gradient(180deg,var(--color-bg) 68%,transparent)}' +
  '.qcat-row::-webkit-scrollbar{display:none}' +
  '.qcat{scroll-snap-align:center;transition:transform .2s ease}' +
  '.qcat.on{transform:translateY(-1px)}' +
  '.qcat-list{touch-action:pan-y}' +
  '</style>'
$hs25 = $doc.IndexOf('</helmet>')
$doc = $doc.Substring(0, $hs25) + $css19 + $doc.Substring($hs25)
# ── 5au. Preferences: Show me as the tiles from sign-up ──────────────────────
#  The same three tiles with their rings and a tick, still allowing two at
#  once the way Preferences always did.
$pseek = @"
          pSeek: [['Women', '#E4485B', ''], ['Men', '#2A3F6E', ''], ['Everyone', '#2A3F6E', '#E4485B']].map(([o, ink, ink2]) => {
            const on = seek.indexOf(o) >= 0, two = !!ink2;
            return {
              label: o, ink, ink2: ink2 || ink, on: on ? '1' : '0', bd: on ? ON : 'rgba(28,37,54,.10)', bg: on ? '#FBF1F0' : '#FBFAF6',
              cx1: two ? '15' : '20', cx2: two ? '25' : '20', r: two ? '10' : '13', sw: two ? '4.2' : '5', op2: two ? '1' : '0',
              pick: () => {
                if (o === 'Everyone') return this.setPref('seek', ['Everyone']);
                let s = seek.filter(x => x !== 'Everyone');
                s = s.indexOf(o) >= 0 ? s.filter(x => x !== o) : s.concat([o]);
                if (!s.length) return;
                this.setPref('seek', s.length === 2 ? ['Everyone'] : s);
              }
            };
          }),
"@
Once8 "          seekOpts: ['Women', 'Men', 'Everyone'].map(o => {" ($pseek + "          seekOpts: ['Women', 'Men', 'Everyone'].map(o => {") 'the tiles values'
$ps0 = $doc.IndexOf('<div class="tgp-seg">', $doc.IndexOf('<div class="tgp-label">Show me</div>', $doc.IndexOf('<sc-if value="{{ at.prefs }}">')))
$pe0 = $doc.IndexOf('</div>', $doc.IndexOf('</sc-for>', $ps0)) + '</div>'.Length
if ($ps0 -lt 0 -or $pe0 -lt $ps0) { throw "Show me control not found" }
$tiles = '<div class="tgb-gender">' + "`n" +
  '                <sc-for list="{{ pSeek }}" as="s" hint-placeholder-count="3">' + "`n" +
  '                  <button type="button" class="tgp-tile tg-tap" style="border-color:{{ s.bd }};background:{{ s.bg }}" sc-camel-on-click="{{ s.pick }}">' + "`n" +
  '                    <svg sc-camel-view-box="0 0 40 40" style="width:30px;height:30px;display:block;overflow:visible" aria-hidden="true"><circle cx="{{ s.cx1 }}" cy="20" r="{{ s.r }}" fill="none" stroke="{{ s.ink }}" stroke-width="{{ s.sw }}"></circle><circle cx="{{ s.cx2 }}" cy="20" r="{{ s.r }}" fill="none" stroke="{{ s.ink2 }}" stroke-width="{{ s.sw }}" style="opacity:{{ s.op2 }}"></circle></svg>' + "`n" +
  '                    <span class="tgp-tiletitle">{{ s.label }}</span>' + "`n" +
  '                    <span class="tgp-tick" style="opacity:{{ s.on }}"><svg width="12" height="12" sc-camel-view-box="0 0 24 24" fill="none" stroke="#FBFAF6" stroke-width="3.4" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7.5"></path></svg></span>' + "`n" +
  '                  </button>' + "`n" +
  '                </sc-for>' + "`n" +
  '              </div>'
$doc = $doc.Substring(0, $ps0) + $tiles + $doc.Substring($pe0)
# ── 5av. Preferences drops the Kids filter ───────────────────────────────────
#  Kids is a tag people choose on their own profile; filtering Discover by it
#  is not wanted.
$k0 = $doc.IndexOf('<div class="tgp-label">Kids</div>', $doc.IndexOf('<sc-if value="{{ at.prefs }}">'))
if ($k0 -lt 0) { throw "Kids block not found" }
$k1 = $doc.IndexOf('<div class="tgp-label">', $k0 + 10)
if ($k1 -lt $k0) { throw "Kids block end not found" }
$doc = $doc.Substring(0, $k0) + $doc.Substring($k1)
# ── 5aw. a living ground under glass ─────────────────────────────────────────
#  Behind every screen two soft pink shapes wander on long loops, each
#  dragging a trail, with a sheet of frosted glass over them. The panels are
#  translucent so the colour moves behind the content. Discover keeps its own
#  photo ground and is left alone.
$phi = $doc.IndexOf('data-tg-phone="1"')
$phg = $doc.IndexOf('>', $phi) + 1
if ($phi -lt 0 -or $phg -lt 1) { throw "phone root not found" }
$blobs = ''
foreach ($k in @('a', 'b')) { foreach ($t in @('', ' t1', ' t2', ' t3')) { $blobs += '<i class="' + $k + $t + '"></i>' } }
$layers = "`n        " + '<div class="tgglow" aria-hidden="true">' + $blobs + '</div>' + "`n        " + '<div class="tgglass" aria-hidden="true"></div>'
$doc = $doc.Substring(0, $phg) + $layers + $doc.Substring($phg)
$css20 = '<style>' +
  '[data-tg-phone]{position:relative;isolation:isolate}' +
  '.tgglow,.tgglass{position:absolute;inset:0;pointer-events:none;border-radius:inherit;overflow:hidden}' +
  '.tgglow{z-index:0}' +
  '.tgglass{z-index:1;-webkit-backdrop-filter:blur(26px) saturate(1.35);backdrop-filter:blur(26px) saturate(1.35);' +
  'background:linear-gradient(180deg,rgba(255,252,248,.3),rgba(255,251,246,.3));box-shadow:inset 0 1px 0 rgba(255,255,255,.55)}' +
  '[data-tg-phone] > *:not(.tgglow):not(.tgglass){position:relative;z-index:2}' +
  '.tgglow i{position:absolute;display:block;width:86%;aspect-ratio:1;border-radius:50%;filter:blur(42px);will-change:transform;transform:translate3d(0,0,0);' +
  'background:radial-gradient(circle at 50% 50%,rgba(228,72,91,.9),rgba(228,72,91,0) 66%)}' +
  '.tgglow i.a{top:0;left:0;animation:tgw-a 46s linear infinite}' +
  '.tgglow i.b{bottom:0;top:auto;left:0;animation:tgw-b 58s linear infinite}' +
  '.tgglow i.t1{opacity:.5;filter:blur(54px);animation-delay:-1.3s}' +
  '.tgglow i.t2{opacity:.3;filter:blur(66px);animation-delay:-2.7s}' +
  '.tgglow i.t3{opacity:.16;filter:blur(80px);animation-delay:-4.2s}' +
  '@keyframes tgw-a{0%{transform:translate3d(8%,-50%,0) scale(1)}15%{transform:translate3d(-16%,8%,0) scale(1.1)}32%{transform:translate3d(26%,66%,0) scale(.95)}' +
  '50%{transform:translate3d(-4%,118%,0) scale(1.16)}68%{transform:translate3d(-30%,58%,0) scale(1.02)}85%{transform:translate3d(12%,2%,0) scale(1.08)}' +
  '100%{transform:translate3d(8%,-50%,0) scale(1)}}' +
  '@keyframes tgw-b{0%{transform:translate3d(8%,50%,0) scale(1.05)}18%{transform:translate3d(-18%,-12%,0) scale(.95)}35%{transform:translate3d(22%,-78%,0) scale(1.16)}' +
  '52%{transform:translate3d(-8%,-128%,0) scale(1)}70%{transform:translate3d(-30%,-58%,0) scale(1.1)}88%{transform:translate3d(14%,-6%,0) scale(.98)}' +
  '100%{transform:translate3d(8%,50%,0) scale(1.05)}}' +
  '@media (prefers-reduced-motion:reduce){.tgglow i{animation:none}}' +
  '.tgp-card,.tgb-card,.card,.tgp-tile,.tga,.tga-folded,.tgp-seg,.tgb-wheelcard,.eps-card,' +
  '.tgb-field input.tg-vinput,.tgb-tag,.tga-own,.tgp-range .tgp-track,.tgc-card{' +
  'background-color:rgba(251,250,246,.52) !important;-webkit-backdrop-filter:blur(14px) saturate(1.3);backdrop-filter:blur(14px) saturate(1.3);' +
  'border-color:rgba(255,255,255,.6) !important;box-shadow:inset 0 1px 0 rgba(255,255,255,.7),0 14px 30px -22px rgba(28,37,54,.5) !important}' +
  '.tgp-card > *,.tgb-card > *{background:transparent !important}.tgp-tile{background-image:none !important}' +
  '.card[style*="tg-deep"],.tgp-card[style*="tg-deep"]{background-color:var(--tg-deep) !important;-webkit-backdrop-filter:none !important;backdrop-filter:none !important;border-color:transparent !important;box-shadow:0 18px 40px -24px rgba(28,37,54,.7) !important}' +
  '.ep-bar,.ep-tabs,.lk-head{background:rgba(255,252,248,.4) !important;-webkit-backdrop-filter:blur(18px) saturate(1.3);backdrop-filter:blur(18px) saturate(1.3)}' +
  '[data-tg-phone] .tg-scroll [style*="#F9F1E9"],[data-tg-phone] .tg-scroll [style*="--color-bg"]{background-color:transparent !important}' +
  '</style>'
$hs26 = $doc.IndexOf('</helmet>')
$doc = $doc.Substring(0, $hs26) + $css20 + $doc.Substring($hs26)
# ── 5ax. the ground holds still until The basics ─────────────────────────────
#  On the splash and the sign-in screens the pink rests at the top and the
#  bottom and does not move. From The basics on, it comes alive.
Once8 'data-tg-phone="1"' 'data-tg-phone="1" data-tg-still="{{ stillGround }}"' 'the still flag'
Once8 '      showTabs: tabScreens.indexOf(screen) >= 0,' "      stillGround: ['splash', 'auth', 'login', 'otp'].indexOf(screen) >= 0 ? 'on' : '',`n      showTabs: tabScreens.indexOf(screen) >= 0," 'which screens hold still'
$css21 = '<style>' +
  '[data-tg-still="on"] .tgglow i{animation:none !important}' +
  '[data-tg-still="on"] .tgglow i.t1,[data-tg-still="on"] .tgglow i.t2,[data-tg-still="on"] .tgglow i.t3{display:none}' +
  '[data-tg-still="on"] .tgglow i.a{transform:translate3d(8%,-50%,0) scale(1)}' +
  '[data-tg-still="on"] .tgglow i.b{transform:translate3d(8%,50%,0) scale(1.05)}' +
  '</style>'
$hs27 = $doc.IndexOf('</helmet>')
$doc = $doc.Substring(0, $hs27) + $css21 + $doc.Substring($hs27)
# ── 5ay. the photo melts into the page ───────────────────────────────────────
#  No rounded corners at the foot of the main photo, and its last stretch
#  fades out so the scroll from photo to cards is soft rather than a cut.
$css22 = '<style>' +
  '.tgd-hero{border-radius:0 !important;overflow:visible !important}' +
  '.tgd-hero-img,.tgd-hero-shade{-webkit-mask-image:linear-gradient(180deg,#000 calc(100% - 54px),rgba(0,0,0,.55) calc(100% - 22px),rgba(0,0,0,0) 100%);' +
  'mask-image:linear-gradient(180deg,#000 calc(100% - 54px),rgba(0,0,0,.55) calc(100% - 22px),rgba(0,0,0,0) 100%)}' +
  '.tgd-hero-img{border-radius:0}' +
  '.tgd-hero::after{content:"";position:absolute;left:0;right:0;bottom:-6px;height:56px;z-index:1;pointer-events:none;' +
  '-webkit-backdrop-filter:blur(7px);backdrop-filter:blur(7px);' +
  '-webkit-mask-image:linear-gradient(180deg,rgba(0,0,0,0),#000 70%);mask-image:linear-gradient(180deg,rgba(0,0,0,0),#000 70%)}' +
  '.tgd-hero-info,.tgs-strip,.tgd-heart,.ep-mainedit{z-index:3}' +
  '</style>'
$hs28 = $doc.IndexOf('</helmet>')
$doc = $doc.Substring(0, $hs28) + $css22 + $doc.Substring($hs28)
# ── 5az. dark ───────────────────────────────────────────────────────────────
#  The whole app moves onto a deep plum ground, so Discover and everything
#  else read as one system. The pink still wanders over it, now lighting the
#  ground rather than tinting it. Panels become dark glass with a lit edge.
$nInk = ([regex]::Matches($doc, [regex]::Escape('color:rgba(28,37,54,'))).Count + ([regex]::Matches($doc, [regex]::Escape('color:#1C2536'))).Count
$doc = $doc.Replace('color:rgba(28,37,54,', 'color:rgba(242,234,230,').Replace('color:#1C2536', 'color:#F2EAE6')
Write-Output ("dark: lifted {0} hard-coded ink colours" -f $nInk)
$doc = $doc.Replace("'#1C2536' : 'rgba(28,37,54,.65)'", "'#F2EAE6' : 'rgba(242,234,230,.62)'")
$doc = $doc.Replace("'#1C2536' : 'rgba(28,37,54,.62)'", "'#F2EAE6' : 'rgba(242,234,230,.62)'")
$doc = $doc.Replace("'rgba(28,37,54,", "'rgba(242,234,230,")
$doc = [regex]::Replace($doc, 'color:rgba\(242,234,230,\s*\.(\d+)\)', {
  param($m)
  $v = [double]("0." + $m.Groups[1].Value)
  if ($v -lt 0.58) { 'color:rgba(242,234,230,.66)' } else { $m.Value }
})
$doc = [regex]::Replace($doc, 'color:color-mix\(in srgb,var\(--color-text\)\s*(\d+)%', {
  param($m)
  $p = [int]$m.Groups[1].Value
  if ($p -lt 58) { 'color:color-mix(in srgb,var(--color-text) 66%' } else { $m.Value }
})
$nPrem = 0
$doc = [regex]::Replace($doc, '<div([^>]*?)style="([^"]*?)background:var\(--tg-deep\)', {
  param($m)
  $script:nPrem++
  '<div data-prem="1"' + $m.Groups[1].Value + 'style="' + $m.Groups[2].Value + 'background:var(--tg-deep)'
})
Write-Output ("dark: {0} premium panels" -f $nPrem)
$css23 = '<style>' +
  '[data-tg-phone]{' +
  '--color-bg:#140D14;--color-surface:#1C141C;--color-text:#F2EAE6;--color-divider:rgba(255,255,255,.12);' +
  '--color-accent-800:rgba(242,234,230,.62);--color-accent-900:#F2EAE6;' +
  '--color-accent-100:#33202B;--color-accent-200:#472A38;--color-accent-300:#6B3B4B;' +
  '--color-neutral-100:#1C141C;--color-neutral-200:#241A24;--color-neutral-300:#332633;' +
  '--color-neutral-400:rgba(242,234,230,.62);--color-neutral-500:rgba(242,234,230,.7);' +
  '--tg-glow:#F0566E;--tg-ink:#F2EAE6;' +
  'background:radial-gradient(120% 52% at 50% -12%,#32192C 0%,rgba(50,25,44,0) 62%),' +
  'radial-gradient(90% 40% at 100% 104%,#3A1C2A 0%,rgba(58,28,42,0) 70%),' +
  'linear-gradient(180deg,#1A1018 0%,#140D14 55%,#100A10 100%) !important;color:#F2EAE6}' +
  '.tgglow i{background:radial-gradient(circle at 50% 50%,rgba(240,86,110,.72),rgba(240,86,110,0) 66%) !important;mix-blend-mode:screen;filter:blur(48px)}' +
  '.tgglow i.t1{opacity:.4}.tgglow i.t2{opacity:.24}.tgglow i.t3{opacity:.12}' +
  '.tgglass{background:linear-gradient(180deg,rgba(16,10,16,.3),rgba(16,10,16,.38)) !important;' +
  '-webkit-backdrop-filter:blur(28px) saturate(1.15);backdrop-filter:blur(28px) saturate(1.15);box-shadow:inset 0 1px 0 rgba(255,255,255,.06) !important}' +
  '.tgp-card,.tgb-card,.card,.tgp-tile,.tga,.tga-folded,.tgp-seg,.tgb-wheelcard,.eps-card,.tgc-card,' +
  '.tgb-field input.tg-vinput,.tgb-tag,.tga-own,.tga-opt,.tgp-chips > button,.tgc-sw{' +
  'background-color:rgba(255,255,255,.055) !important;border-color:rgba(255,255,255,.12) !important;' +
  'box-shadow:inset 0 1px 0 rgba(255,255,255,.08),0 18px 36px -26px #000 !important;color:#F2EAE6 !important}' +
  '.tgp-card > *,.tgb-card > *{background:transparent !important}' +
  '.tgp-row,.tgp-linkrow,.tga-cat,.tgv-hrow{border-color:rgba(255,255,255,.08) !important}' +
  '.tgp-tile.on,.tga-opt.on{background-color:rgba(240,86,110,.18) !important;border-color:#F0566E !important;box-shadow:inset 0 0 0 1px #F0566E !important}' +
  '.tgp-sw{background:rgba(255,255,255,.14) !important}' +
  '.tga-preview{border-color:rgba(255,255,255,.16) !important;background:rgba(255,255,255,.035) !important}' +
  '.tga-ptags .tg-tag{color:#F2EAE6 !important;background:rgba(255,255,255,.06) !important;border-color:rgba(255,255,255,.14) !important}' +
  '.tgc-empty{background:transparent !important;border-color:rgba(255,255,255,.16) !important;box-shadow:none !important}' +
  '.tgc-txt b{color:#F2EAE6}.tgc-txt small{color:rgba(242,234,230,.62)}' +
  '.tgc-plus{background:rgba(255,255,255,.07) !important;color:rgba(242,234,230,.6) !important}' +
  '.tgc-open{background:#F0566E !important;color:#160F16 !important}' +
  '.tga-add{background:#F0566E !important;color:#160F16 !important}' +
  '.tgv-height b{color:rgba(242,234,230,.5)}.tgv-height b.on{color:#F2EAE6}' +
  '.tgv-step{background:rgba(255,255,255,.06) !important;border-color:rgba(255,255,255,.14) !important;color:#F2EAE6 !important}' +
  '.lv-note p{color:#F2EAE6 !important}' +
  '.ep-mainedit{color:#F2EAE6 !important}' +
  '.tgd-bar,.ep-bar,.ep-tabs,.lk-head,.tgd-bar.tgd-one{background:rgba(18,11,18,.45) !important;' +
  '-webkit-backdrop-filter:blur(20px) saturate(1.2);backdrop-filter:blur(20px) saturate(1.2)}' +
  '.qcat-row{background:linear-gradient(180deg,rgba(18,11,18,.85) 68%,transparent) !important}' +
  '[data-tg-phone] circle[stroke="#2A3F6E"],[data-tg-phone] path[stroke="#2A3F6E"]{stroke:#93A9E0}' +
  '[data-tg-phone] [fill="#2A3F6E"]{fill:#93A9E0}' +
  '#tgSurf{background:linear-gradient(180deg,rgba(24,15,24,.62),rgba(20,12,20,.78)) !important;border-top-color:rgba(255,255,255,.1) !important;' +
  'box-shadow:inset 0 1px 0 rgba(255,255,255,.08),0 -20px 40px -22px #000 !important}' +
  '.tgTab svg,.tgTab span{color:rgba(246,238,234,.72) !important}' +
  '.tgTab.on svg,.tgTab.on span,.tgTab.hot svg,.tgTab.hot span{color:#F0566E !important}' +
  '#tgBar #tgHub,#tgBar:not(.open) #tgHub,#tgBar.open #tgHub,#tgBar.open #tgHub.on,#tgHub.hot,#tgHub.conn{' +
  'background:linear-gradient(170deg,rgba(255,255,255,.14),rgba(255,255,255,0) 46%),rgba(255,255,255,.05) !important;' +
  '-webkit-backdrop-filter:blur(10px) saturate(1.25);backdrop-filter:blur(10px) saturate(1.25);' +
  'box-shadow:inset 0 0 0 1.4px rgba(240,86,110,.95),inset 0 1.6px 0 rgba(255,255,255,.4),' +
  'inset 0 -8px 12px -8px rgba(0,0,0,.45),0 0 18px -3px rgba(240,86,110,.6),0 14px 26px -14px #000 !important}' +
  '#tgHub::before,#tgHub::after{content:none !important}' +
  '#tgHub svg circle:first-child{stroke:#F6EEEA !important}' +
  '#tgHub svg circle:last-child,#tgHub svg .ring2{stroke:#F0566E !important}' +
  '#tgHub.conn{box-shadow:inset 0 0 0 1.4px rgba(240,86,110,.95),inset 0 1.6px 0 rgba(255,255,255,.4),' +
  'inset 0 -8px 12px -8px rgba(0,0,0,.45),0 0 22px -2px rgba(240,86,110,.8),0 0 0 4px rgba(240,86,110,.14),0 14px 26px -14px #000 !important}' +
  '.tgd-root .tgt-card,.tgd-root .tgt-tone .tgt-card,.tgd-root .tgt-voice{' +
  'background:color-mix(in srgb,var(--pv) 26%,rgba(18,12,18,.55)) !important;color:#F2EAE6 !important}' +
  '.tgd-root .tgt-q{color:rgba(242,234,230,.62) !important}' +
  '.tgd-root .tgt-a,.tgd-root .tgt-dtl > span{color:#F2EAE6 !important}' +
  '.tgd-root .tgd-heart button,.tgd-root .tgt-heart,.tgs-likecue{background:color-mix(in srgb,var(--pv) 26%,rgba(18,12,18,.5)) !important}' +
  '.tag,.tag-neutral{background:rgba(255,255,255,.07) !important;color:rgba(242,234,230,.8) !important;border-color:rgba(255,255,255,.14) !important}' +
  '.tag-accent{background:rgba(240,86,110,.2) !important;color:#FFC2CC !important;border-color:rgba(240,86,110,.5) !important}' +
  '[data-prem]{background:linear-gradient(158deg,rgba(240,86,110,.22) 0%,rgba(87,48,79,.38) 44%,rgba(26,16,24,.76) 100%) !important;' +
  '-webkit-backdrop-filter:blur(18px) saturate(1.3);backdrop-filter:blur(18px) saturate(1.3);' +
  'border:1px solid rgba(255,255,255,.14) !important;' +
  'box-shadow:inset 0 1px 0 rgba(255,255,255,.2),inset 0 0 40px -14px rgba(240,86,110,.5),' +
  '0 0 0 1px rgba(240,86,110,.14),0 26px 50px -30px #000 !important}' +
  '[data-prem] *{color:#F6EEEA !important;background-color:transparent !important;border-color:transparent !important;box-shadow:none !important}' +
  '[data-prem] span[style*="uppercase"]{color:#FFB6C3 !important;letter-spacing:.14em !important}' +
  '[data-prem] svg{color:#FFB6C3 !important;stroke:#FFB6C3 !important}' +
  '[data-prem] .btn:not(.btn-ghost){background:linear-gradient(168deg,#FF7488,#E4485B) !important;border:0 !important;' +
  'box-shadow:inset 0 1px 0 rgba(255,255,255,.45),0 14px 28px -14px rgba(240,86,110,.95) !important}' +
  '[data-prem] .btn:not(.btn-ghost),[data-prem] .btn:not(.btn-ghost) *{color:#1A1018 !important;font-weight:500}' +
  '[data-prem] .btn-ghost,[data-prem] .btn-ghost *{color:rgba(246,238,234,.62) !important}' +
  '[data-prem] [style*="underline"]{color:#FFD4DC !important}' +  '.tgd-vdur,.tgt-dur,.tgd-dur{color:#F2EAE6 !important}' +
  'html,body{background:#120C12 !important}' +
  '[style*="100dvh"]{background:#120C12 !important;color:rgba(242,234,230,.7) !important}' +
  '[data-tg-caption]{color:rgba(242,234,230,.45) !important}' +
  '</style>'
$hs29 = $doc.IndexOf('</helmet>')
$doc = $doc.Substring(0, $hs29) + $css23 + $doc.Substring($hs29)
# ── 5ba. phone proportions, and every screen opens at the top ───────────────
#  The frame keeps a phone's proportions without dressing up as one, and
#  changing screen always returns to the top.
Once8 '  componentDidUpdate() { this.applyLang(); this.applyAccent(); this.applyWheels(); this.qSync(); }' ("  componentDidUpdate() { this.applyLang(); this.applyAccent(); this.applyWheels(); this.qSync(); this.toTop(); }`n" +
  "  // a new screen always starts at its top`n" +
  "  toTop() {`n" +
  "    const k = this.state.screen + '|' + (this.state.tab || '');`n" +
  "    if (this._lastScreen === k) return;`n" +
  "    this._lastScreen = k;`n" +
  "    const sc = document.querySelector('.tg-scroll');`n" +
  "    if (sc) sc.scrollTop = 0;`n" +
  "  }") 'back to the top'
$css24 = '<style>' +
  '[data-tg-frame]{background:#0E0A0E !important;padding:10px !important;border-radius:50px !important;' +
  'box-shadow:inset 0 0 0 1px rgba(255,255,255,.08),0 30px 70px -34px #000 !important}' +
  '[data-tg-frame] [data-tg-phone]{border-radius:42px !important;overflow:hidden}' +
  '</style>'
$hs30 = $doc.IndexOf('</helmet>')
$doc = $doc.Substring(0, $hs30) + $css24 + $doc.Substring($hs30)
# ── 5bb. the like sheet, in the dark system ──────────────────────────────────
#  The sheet becomes dark glass with rounded shoulders, the note field reads,
#  the photo is rounded, and the ring button is glass with a rose edge.
$lk = $doc.IndexOf('<sc-if value="{{ overlay.like }}">')
if ($lk -lt 0) { throw "like sheet not found" }
$sheet = '<div style="background:var(--color-surface);border-start-start-radius:3px;border-start-end-radius:3px;padding:var(--space-4) var(--space-4) var(--space-6);animation:tg-up .28s ease"'
$at = $doc.IndexOf($sheet, $lk)
if ($at -lt 0) { throw "like sheet panel not found" }
$doc = $doc.Substring(0, $at) + $sheet.Replace('<div style=', '<div data-sheet="1" style=') + $doc.Substring($at + $sheet.Length)
$css25 = '<style>' +
  '[data-sheet]{background:linear-gradient(180deg,rgba(46,29,42,.9),rgba(22,14,22,.96)) !important;' +
  '-webkit-backdrop-filter:blur(24px) saturate(1.25);backdrop-filter:blur(24px) saturate(1.25);' +
  'border-start-start-radius:26px !important;border-start-end-radius:26px !important;' +
  'border-top:1px solid rgba(255,255,255,.14);box-shadow:0 -26px 60px -30px #000,inset 0 1px 0 rgba(255,255,255,.18) !important;' +
  'padding-bottom:calc(var(--space-6) + env(safe-area-inset-bottom)) !important}' +
  '[data-sheet] .lk-head{background:transparent !important;-webkit-backdrop-filter:none !important;backdrop-filter:none !important;' +
  'box-shadow:none !important;border:0 !important;margin:2px -4px 10px !important;min-height:34px !important}' +
  '[data-sheet] .lk-grab{top:-2px !important;background:rgba(255,255,255,.22) !important}' +
  '[data-sheet] .lk-x{background:rgba(255,255,255,.08) !important;box-shadow:inset 0 0 0 1px rgba(255,255,255,.18) !important}' +
  '[data-sheet] .lk-x svg{stroke:#F2EAE6 !important}' +
  '[data-sheet] > div[style*="height:190px"],[data-sheet] > div[style*="height: 190px"]{border-radius:18px !important;' +
  'box-shadow:0 20px 44px -20px #000,inset 0 0 0 1px rgba(255,255,255,.12) !important}' +
  '[data-sheet] .input,[data-sheet] textarea{background:rgba(255,255,255,.055) !important;color:#F2EAE6 !important;' +
  'border:1px solid rgba(255,255,255,.14) !important;border-radius:16px !important}' +
  '[data-sheet] textarea::placeholder{color:rgba(242,234,230,.4) !important}' +
  '[data-sheet] textarea:focus{outline:none;border-color:rgba(240,86,110,.6) !important;background:rgba(255,255,255,.08) !important}' +
  '[data-sheet] .btn[style*="#E4485B"],[data-sheet] .btn[style*="228, 72, 91"]{border-radius:999px !important;background:linear-gradient(168deg,#FF7488,#E4485B) !important;' +
  'color:#1A1018 !important;box-shadow:inset 0 1px 0 rgba(255,255,255,.45),0 16px 30px -16px rgba(240,86,110,.95) !important}' +
  '[data-sheet] .btn[style*="tg-clay"]{border-radius:999px !important;background:rgba(255,255,255,.05) !important;' +
  'color:#FF9AAB !important;border:1.4px solid rgba(240,86,110,.7) !important;' +
  '-webkit-backdrop-filter:blur(10px);backdrop-filter:blur(10px);box-shadow:inset 0 1px 0 rgba(255,255,255,.16) !important}' +
  '[data-sheet] .btn[style*="tg-clay"] svg{stroke:#FF9AAB !important}' +
  '[data-sheet] div[style*="rgba(87, 48, 79"]{background:rgba(240,86,110,.1) !important;border-color:rgba(240,86,110,.26) !important;border-radius:18px !important}' +
  '[data-sheet] span[style*="rgb(87, 48, 79"],[data-sheet] div[style*="rgba(87, 48, 79"] span{color:#FFB0BF !important}' +
  '</style>'
$hs31 = $doc.IndexOf('</helmet>')
$doc = $doc.Substring(0, $hs31) + $css25 + $doc.Substring($hs31)
# ── 5bc. everything after a like, in the dark system ────────────────────────
#  The dialogs become the same dark glass as the like sheet, the match
#  screen moves onto the dark ground, fields stop being white paper, and
#  the simulate shortcuts stay deliberately just below sight.
$toastOld = '<span style="background:#FBFAF6;color:#F2EAE6;border:1px solid rgba(28,37,54,.08);border-radius:3px;padding:9px 14px;font-size:13.5px;line-height:1.35;text-align:center;box-shadow:0 6px 20px rgba(28,37,54,.14);max-width:320px"'
$toastNew = '<span data-toast="1" style="background:rgba(30,19,28,.86);color:#F2EAE6;border:1px solid rgba(255,255,255,.16);border-radius:999px;padding:10px 16px;font-size:13.5px;line-height:1.35;text-align:center;box-shadow:0 18px 38px -18px #000;max-width:320px"'
Once8 $toastOld $toastNew 'toast'

$nBord = ([regex]::Matches($doc, [regex]::Escape('solid rgba(28,37,54,'))).Count
$doc = $doc.Replace('solid rgba(28,37,54,', 'solid rgba(242,234,230,')
Write-Output ("dark: lifted {0} ink borders" -f $nBord)

$nDlg = 0
$doc = [regex]::Replace($doc, '<div style="background:var\(--color-surface\);border-radius:3px;padding:var\(--space-6\)', {
  param($m)
  $script:nDlg++
  '<div data-dlg="1" style="background:var(--color-surface);border-radius:3px;padding:var(--space-6)'
})
if ($nDlg -lt 7) { throw "dialog panels not marked" }

$nSh = 0
$doc = [regex]::Replace($doc, '<div style="background:var\(--color-surface\);border-start-start-radius:3px', {
  param($m)
  $script:nSh++
  '<div data-sheet="1" style="background:var(--color-surface);border-start-start-radius:3px'
})

$nScrim = 0
$doc = [regex]::Replace($doc, '<div style="position:absolute;inset:0;z-index:(9|10);background:color-mix\(in srgb,var\(--color-neutral-900\)', {
  param($m)
  $script:nScrim++
  '<div data-scrim="1" style="position:absolute;inset:0;z-index:' + $m.Groups[1].Value + ';background:color-mix(in srgb,var(--color-neutral-900)'
})
Write-Output ("dark: {0} dialogs, {1} sheets, {2} scrims" -f $nDlg, $nSh, $nScrim)

$nIcon = 0
$doc = [regex]::Replace($doc, '<div style="width:(64|60)px;height:(?:64|60)px;border-radius:999px;background:', {
  param($m)
  $script:nIcon++
  '<div data-dlgicon="1" style="width:' + $m.Groups[1].Value + 'px;height:' + $m.Groups[1].Value + 'px;border-radius:999px;background:'
})
if ($nIcon -lt 2) { throw "dialog icons not marked" }

$nSim = 0
$doc = [regex]::Replace($doc, '<button class="btn btn-ghost tg-tap"([^>]*?)sc-camel-on-click="\{\{ (simulateMatch|simulateCheckin|waitSim) \}\}"', {
  param($m)
  $script:nSim++
  '<button data-sim="1" class="btn btn-ghost tg-tap"' + $m.Groups[1].Value + 'sc-camel-on-click="{{ ' + $m.Groups[2].Value + ' }}"'
})
if ($nSim -lt 2) { throw "simulate shortcuts not marked" }

$mOld = '<div style="position:absolute;inset:0;z-index:9;background:#F9F1E9;background-image:radial-gradient(62% 34% at 50% 22%,rgba(235,182,190,.34),transparent 70%),radial-gradient(70% 40% at 50% 104%,rgba(87,48,79,.40),transparent 72%)'
$mNew = '<div data-match="1" style="position:absolute;inset:0;z-index:9;background:rgba(13,8,13,.84);background-image:radial-gradient(64% 38% at 50% 18%,rgba(240,86,110,.34),transparent 70%),radial-gradient(80% 46% at 50% 106%,rgba(87,48,79,.62),transparent 74%);-webkit-backdrop-filter:blur(26px) saturate(1.2);backdrop-filter:blur(26px) saturate(1.2)'
Once8 $mOld $mNew 'match screen'

Once8 'background:var(--color-accent-2-200);animation:tg-breathe' 'background:radial-gradient(circle at 50% 50%,rgba(240,86,110,.5),rgba(240,86,110,0) 70%);animation:tg-breathe' 'waiting halo'
Once8 'color:#D6B0EC' 'color:#FFAEBD' 'chat kicker'

$css26 = '<style>' +
  '[data-tg-phone]{--tg-sub:rgba(242,234,230,.66);--tg-mute:rgba(242,234,230,.44);--tg-glass-line:rgba(255,255,255,.16);' +
  '--color-accent-700:#FF8FA1;--color-accent-2-700:rgba(242,234,230,.62);' +
  '--color-accent-2-800:rgba(242,234,230,.62);--color-accent-2-900:#F2EAE6}' +
  '[data-scrim]{background:rgba(10,6,11,.58) !important;-webkit-backdrop-filter:blur(10px) saturate(1.1);backdrop-filter:blur(10px) saturate(1.1)}' +
  '[data-dlg]{background:linear-gradient(180deg,rgba(46,29,42,.92),rgba(20,13,20,.96)) !important;' +
  '-webkit-backdrop-filter:blur(26px) saturate(1.25);backdrop-filter:blur(26px) saturate(1.25);' +
  'border-radius:26px !important;border:1px solid rgba(255,255,255,.13) !important;' +
  'box-shadow:inset 0 1px 0 rgba(255,255,255,.2),0 0 0 1px rgba(240,86,110,.1),0 34px 70px -28px #000 !important}' +
  '[data-dlg] h3{color:#F6EEEA !important}' +
  '[data-dlg] p{color:rgba(242,234,230,.66) !important}' +
  '[data-dlgicon]{background:linear-gradient(168deg,#FF7488,#E4485B) !important;' +
  'box-shadow:inset 0 1.4px 0 rgba(255,255,255,.5),0 18px 34px -16px rgba(240,86,110,.9) !important}' +
  '[data-dlgicon] svg{stroke:#1A1018 !important}' +
  '[data-dlg] .btn-primary,[data-match] .btn{border-radius:999px !important;' +
  'background:linear-gradient(168deg,#FF7488,#E4485B) !important;border:0 !important;' +
  'box-shadow:inset 0 1px 0 rgba(255,255,255,.45),0 16px 30px -16px rgba(240,86,110,.95) !important}' +
  '[data-dlg] .btn-primary,[data-dlg] .btn-primary *,[data-match] .btn,[data-match] .btn *{color:#1A1018 !important}' +
  '[data-dlg] .btn-secondary,[data-sheet] .btn-secondary{border-radius:999px !important;' +
  'background:rgba(255,255,255,.055) !important;color:#F2EAE6 !important;' +
  'border:1px solid rgba(255,255,255,.16) !important;box-shadow:inset 0 1px 0 rgba(255,255,255,.1) !important}' +
  '[data-dlg] .btn[style*="transparent"]{border-radius:999px !important;border-color:rgba(240,86,110,.6) !important;color:#FF9AAB !important}' +
  '[data-match] h2{color:#F6EEEA !important;text-shadow:0 10px 34px rgba(0,0,0,.55)}' +
  '[data-match] p{color:rgba(242,234,230,.74) !important}' +
  '[data-match] img{filter:drop-shadow(0 18px 44px rgba(240,86,110,.45))}' +
  '[data-toast]{-webkit-backdrop-filter:blur(16px) saturate(1.2);backdrop-filter:blur(16px) saturate(1.2)}' +
  '.card-kicker{color:#FFAEBD !important}' +
  '.input,select.input,textarea.input{background:rgba(255,255,255,.055) !important;color:#F2EAE6 !important;' +
  'border:1px solid rgba(255,255,255,.14) !important}' +
  '.input::placeholder,textarea.input::placeholder{color:rgba(242,234,230,.4) !important}' +
  '.input:focus,textarea.input:focus{outline:none;border-color:rgba(240,86,110,.6) !important;' +
  'background:rgba(255,255,255,.08) !important}' +
  '[data-sim],[data-sim]:hover{color:rgba(242,234,230,.06) !important;text-shadow:none !important}' +
  '.btn-primary,.btn-primary *{color:#1A1018 !important}' +
  '.btn-primary{border-radius:999px !important;background:linear-gradient(168deg,#FF7488,#E4485B) !important;' +
  'background-image:linear-gradient(168deg,#FF7488,#E4485B) !important;border:0 !important;' +
  'box-shadow:inset 0 1px 0 rgba(255,255,255,.45),0 16px 30px -16px rgba(240,86,110,.95) !important}' +
  '.btn-primary[disabled],.btn-primary:disabled{background:rgba(255,255,255,.06) !important;' +
  'background-image:none !important;box-shadow:none !important}' +
  '.btn-primary[disabled],.btn-primary:disabled,.btn-primary[disabled] *{color:rgba(242,234,230,.5) !important}' +
  '</style>'
$hs32 = $doc.IndexOf('</helmet>')
$doc = $doc.Substring(0, $hs32) + $css26 + $doc.Substring($hs32)
# the round the chips point at is the round in view, even after a re-render
$qsI = $doc.IndexOf('  qSync() {')
$qsJ = $doc.IndexOf('  qDown(e) {', $qsI)
if ($qsI -lt 0 -or $qsJ -lt 0) { throw 'qSync not found' }
$doc = $doc.Substring(0, $qsI) + ([System.IO.File]::ReadAllText("$scratch\qsync.js.txt", [System.Text.Encoding]::UTF8).TrimEnd()) + [Environment]::NewLine + $doc.Substring($qsJ)
# ── 5bd. the question categories sit on the page, not on a black slab ───────
#  The sticky row had a near-black band behind it with hard edges. It now
#  bleeds to both edges as blurred glass that fades out downwards, and the
#  category you are in reads as rose again — the dark tag rule had flattened it.
$css27 = '<style>' +
  '.qcat-row{margin-inline:calc(var(--space-4) * -1) !important;' +
  'padding:8px var(--space-4) 16px !important;margin-bottom:var(--space-2) !important;' +
  'background:linear-gradient(180deg,rgba(20,13,20,.5),rgba(20,13,20,.16) 74%,rgba(20,13,20,0)) !important;' +
  '-webkit-backdrop-filter:blur(14px) saturate(1.15);backdrop-filter:blur(14px) saturate(1.15);' +
  '-webkit-mask-image:linear-gradient(180deg,#000 0,#000 78%,transparent 100%);' +
  'mask-image:linear-gradient(180deg,#000 0,#000 78%,transparent 100%)}' +
  '.qcat{border-radius:999px !important}' +
  '.qcat.on,.qcat.on:hover{background:linear-gradient(168deg,#FF7488,#E4485B) !important;' +
  'color:#1A1018 !important;border-color:transparent !important;' +
  'box-shadow:inset 0 1px 0 rgba(255,255,255,.45),0 10px 20px -10px rgba(240,86,110,.9) !important}' +
  '.qcat-sub{margin-top:0 !important}' +
  '</style>'
$hs33 = $doc.IndexOf('</helmet>')
$doc = $doc.Substring(0, $hs33) + $css27 + $doc.Substring($hs33)
# ── 5be. Discover keeps its dark ground when the deck runs out ──────────────
#  Each profile tints the page, but the tint was mixed from the person's
#  light colour — fine on cream, a grey slab on dark. It becomes a soft
#  wash of their colour over the ground, and the end-of-deck card becomes
#  the same glass as every other panel.
$emptyOld = '<div style="display:flex;flex-direction:column;align-items:center;text-align:center;gap:10px;padding:var(--space-8) var(--space-4);border-radius:3px;background:var(--color-surface);border:1px solid var(--color-divider)">'
Once8 $emptyOld ($emptyOld.Replace('<div style=', '<div data-empty="1" style=')) 'end of deck card'
$css28 = '<style>' +
  '.tgd-root{background:linear-gradient(180deg,color-mix(in srgb,var(--pv) 15%,transparent) 0,' +
  'color-mix(in srgb,var(--pv) 6%,transparent) 540px,transparent 1100px) !important}' +
  '.tgd-root .tgd-bar{background:rgba(18,11,18,.45) !important}' +
  '[data-empty]{border-radius:26px !important;margin-top:12vh !important;' +
  'background:linear-gradient(180deg,rgba(46,29,42,.72),rgba(20,13,20,.82)) !important;' +
  '-webkit-backdrop-filter:blur(22px) saturate(1.2);backdrop-filter:blur(22px) saturate(1.2);' +
  'border:1px solid rgba(255,255,255,.12) !important;' +
  'box-shadow:inset 0 1px 0 rgba(255,255,255,.16),0 30px 60px -30px #000 !important}' +
  '[data-empty] h3{color:#F6EEEA !important}' +
  '[data-empty] p{color:rgba(242,234,230,.66) !important}' +
  '</style>'
$hs34 = $doc.IndexOf('</helmet>')
$doc = $doc.Substring(0, $hs34) + $css28 + $doc.Substring($hs34)
# ── 5bf. one identity for every profile ────────────────────────────────────
#  Each person used to colour their own page from their photo's palette, so
#  a bright photo made a bright page and the app fell into two designs. The
#  profile now wears one dark set of tokens — the deep violet that already
#  made Shira read as part of the app — while the photo behind still carries
#  that person's vibe, only much darker.
$css29 = '<style>' +
  '.tgd-root,.ep-view,.tgv{--pv:#5F4AB5 !important;--pd:#20193E !important;--pl:#DFDBF0 !important}' +
  '[data-tg-phone] .tg-scroll .tgd-bar,[data-tg-phone] .tg-scroll .tgd-bar.tgd-one,' +
  '[data-tg-phone] .tg-scroll .ep-bar,[data-tg-phone] .tg-scroll .ep-tabs{' +
  'background:linear-gradient(180deg,rgba(14,9,15,.86),rgba(14,9,15,.6)) !important;' +
  '-webkit-backdrop-filter:blur(20px) saturate(1.15) !important;backdrop-filter:blur(20px) saturate(1.15) !important;' +
  'box-shadow:inset 0 -1px 0 rgba(255,255,255,.06) !important}' +
  '.tgd-hero-shade{background:linear-gradient(to top,rgba(12,8,18,.94) 0%,rgba(13,9,19,.82) 10%,' +
  'rgba(15,10,21,.55) 20%,rgba(17,11,23,.26) 27%,rgba(17,11,23,0) 34%),' +
  'linear-gradient(to bottom,rgba(12,8,14,.22) 0%,rgba(12,8,14,0) 14%) !important}' +
  '.tgd-backdrop-img{filter:blur(15px) saturate(.95) brightness(.4) !important;transform:scale(1.08) !important}' +
  '.tgd-backdrop::after{background:linear-gradient(180deg,rgba(16,10,18,.44) 0%,rgba(16,10,18,.58) 38%,rgba(12,8,14,.86) 100%) !important}' +
  '.tgd-root .tgt-dtl > span,.ep-view .tgt-dtl > span,.tgd-root .tg-tag,.ep-view .tg-tag{' +
  'background:color-mix(in srgb,#5F4AB5 24%,rgba(18,12,24,.58)) !important;color:#F2EAE6 !important;' +
  'border:1px solid rgba(255,255,255,.14) !important;' +
  'box-shadow:inset 0 1px 0 rgba(255,255,255,.12),0 8px 18px -12px #000 !important}' +
  '.ep-counters > span{background:rgba(255,255,255,.055) !important;border-color:rgba(255,255,255,.12) !important;' +
  'color:rgba(242,234,230,.62) !important;border-radius:16px !important;' +
  'box-shadow:inset 0 1px 0 rgba(255,255,255,.08) !important}' +
  '.ep-counters b{color:#F2EAE6 !important}' +
  '.ep-mainedit,.ep-badge,.tgt-voice.ep-tile .ep-badge{' +
  'background:color-mix(in srgb,#5F4AB5 24%,rgba(14,9,16,.66)) !important;color:#F2EAE6 !important;' +
  'border:1px solid rgba(255,255,255,.16) !important;' +
  'box-shadow:inset 0 1px 0 rgba(255,255,255,.14),0 10px 22px -12px #000 !important}' +
  '</style>'
$hs35 = $doc.IndexOf('</helmet>')
$doc = $doc.Substring(0, $hs35) + $css29 + $doc.Substring($hs35)
# ── 6. give the tab bar the hook the new bar layer needs, and make check-in reachable ──
$doc = [regex]::Replace($doc, '(<sc-if value="\{\{ showTabs \}\}">\s*<div )style=', '${1}data-tg-tabs="1" style=')
if ($doc -notmatch 'data-tg-tabs') { throw "tab bar hook not applied" }

$doc = [regex]::Replace($doc, '(>End this connection</button>)',
    '${1}' + "`n                <button data-sim=""1"" class=""btn btn-ghost tg-tap"" style=""font-size:12.5px;margin-top:2px"" sc-camel-on-click=""{{ simulateCheckin }}"">Simulate: three days of silence</button>")
if ($doc -notmatch 'simulateCheckin') { throw "check-in trigger not added" }
$simMatch = "simulateMatch: () => this.setState({ overlay: 'match', matched: true }),"
if ($doc.Contains($simMatch)) {
    $doc = $doc.Replace($simMatch, $simMatch + "`n      simulateCheckin: () => this.setState({ overlay: 'checkin' }),")
}

[System.IO.File]::WriteAllText("$scratch\app-template.rebuilt.dc.html", $doc, $utf8)
Write-Output ("rebuilt template: {0} KB, {1} lines" -f [math]::Round(([System.Text.Encoding]::UTF8.GetByteCount($doc))/1KB,1), ($doc -split "`n").Length)
Write-Output ("otp screen present: {0} | checkin trigger: {1}" -f ($doc -match 'at\.otp'), ($doc -match 'simulateCheckin'))
