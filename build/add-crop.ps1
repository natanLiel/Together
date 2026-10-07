$ErrorActionPreference = 'Stop'

# -- let a photo keep its own shape, and let the person pick what shows -------
#  Every frame in the app fills with "cover", which never squashes a picture
#  but does crop it, and until now it always cropped from the middle. A phone
#  photo is 0.80 wide to tall and a landscape one 1.37, against a frame of
#  0.72 -- so the middle is often the wrong part to keep.
#
#  The fix is a focal point per photo: a background-position the whole app
#  reads, and a sheet that lets you drag the picture around inside the real
#  frame to set it. Nothing is ever scaled unevenly.

$repo = Split-Path $PSScriptRoot -Parent
$f = Join-Path $repo 'build\parts\app-template.rebuilt.dc.html'
$raw = [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8)
$n = 0
function Swap([string]$from, [string]$to, [string]$what) {
  if (-not $script:raw.Contains($from)) { throw "crop: '$what' not found" }
  $i = $script:raw.IndexOf($from)
  $script:raw = $script:raw.Substring(0, $i) + $to + $script:raw.Substring($i + $from.Length)
  $script:n++
}

# 1 - state: where a photo's focal point lives, and the sheet being dragged
Swap 'epFlash: null, me: {' 'epFlash: null, epCrop: null, focus: {}, me: {' 'state'

# 2 - every frame in the app reads the focal point. Two definitions, one for
#     the editor and one inside buildBlocks, both now ask the same map.
$old = "      const shotOf = src => 'center/cover no-repeat url(`"' + src + '`")';"
$new = "      const shotOf = src => ((this.state.focus || {})[src] || 'center') + '/cover no-repeat url(`"' + src + '`")';"
Swap $old $new 'editor shotOf'
$old2 = "    const shotOf = src => 'center/cover no-repeat url(`"' + src + '`")';"
$new2 = "    const shotOf = src => ((this.state.focus || {})[src] || 'center') + '/cover no-repeat url(`"' + src + '`")';"
Swap $old2 $new2 'buildBlocks shotOf'

# 3 - a new photo opens the picker straight away: choose, then place it
$oldAdd = "      this.setItems(items.concat([{ id, kind, src }]));`n      this.setState({ epFlash: id, epIdx: 99 });`n      return;"
$newAdd = "      this.setItems(items.concat([{ id, kind, src }]));`n" +
  "      this.setState({ epFlash: id, epIdx: 99 });`n" +
  "      this.epCropOpen(src, true);`n" +
  "      return;"
Swap $oldAdd $newAdd 'epAdd opens the picker'

# 4 - the methods behind the sheet
$anchor = "  meItems() { return this.state.me.items; }"
$methods = @"
  // -- choosing what shows ---------------------------------------------------
  //  The frame crops with "cover", so only one axis can move: a tall photo
  //  pans up and down, a wide one left and right. The drag is mapped to the
  //  real overflow in pixels, so the picture tracks your finger rather than
  //  sliding at some invented speed.
  epCropOpen(src, isNew) {
    const at = (this.state.focus || {})[src] || '50% 50%';
    const p = at.split(' ');
    this.setState({ epCrop: { src, isNew: !!isNew, x: parseFloat(p[0]) || 50, y: parseFloat(p[1]) || 50 } });
  }
  epCropDown(e) {
    const c = this.state.epCrop; if (!c) return;
    const frame = e.currentTarget.getBoundingClientRect();
    const img = new Image();
    img.src = c.src;
    this._crop = { x0: e.clientX, y0: e.clientY, fx: c.x, fy: c.y, fw: frame.width, fh: frame.height, nw: img.naturalWidth || 3, nh: img.naturalHeight || 4 };
    if (e.currentTarget.setPointerCapture) { try { e.currentTarget.setPointerCapture(e.pointerId); } catch (_) {} }
    if (!this._cropMove) { this._cropMove = ev => this.epCropMove(ev); this._cropUp = () => this.epCropUp(); }
    window.addEventListener('pointermove', this._cropMove);
    window.addEventListener('pointerup', this._cropUp);
    window.addEventListener('pointercancel', this._cropUp);
  }
  epCropMove(e) {
    const d = this._crop, c = this.state.epCrop;
    if (!d || !c) return;
    const scale = Math.max(d.fw / d.nw, d.fh / d.nh);
    const overX = d.nw * scale - d.fw, overY = d.nh * scale - d.fh;
    const clamp = v => Math.max(0, Math.min(100, v));
    const x = overX > 1 ? clamp(d.fx - (e.clientX - d.x0) / overX * 100) : 50;
    const y = overY > 1 ? clamp(d.fy - (e.clientY - d.y0) / overY * 100) : 50;
    this.setState({ epCrop: Object.assign({}, c, { x, y }) });
  }
  epCropUp() {
    this._crop = null;
    window.removeEventListener('pointermove', this._cropMove);
    window.removeEventListener('pointerup', this._cropUp);
    window.removeEventListener('pointercancel', this._cropUp);
  }
  epCropSave() {
    const c = this.state.epCrop; if (!c) return;
    const focus = Object.assign({}, this.state.focus || {});
    focus[c.src] = Math.round(c.x) + '% ' + Math.round(c.y) + '%';
    this.setState({ focus, epCrop: null });
    this.toast(this.isHe() ? 'נשמר' : 'Saved');
  }

$anchor
"@
Swap $anchor $methods 'crop methods'

# 5 - the model the sheet renders from
$oldModel = "        list, counters, adds, sheet, vitals, editTiles, editHero, editStrip, editMain, editCards,"
$newModel = "        list, counters, adds, sheet, crop, vitals, editTiles, editHero, editStrip, editMain, editCards,"
Swap $oldModel $newModel 'editor model keys'

$oldSheet = "      // the sheet for one item"
$newSheet = @"
      // the picker that places a photo inside the frame it has to fill
      const cr = st.epCrop;
      const crop = !cr ? { open: false } : {
        open: true,
        title: he ? 'מה יוצג בתמונה' : 'Choose what shows',
        hint: he ? 'גררו את התמונה. היא לא נמתחת — רק מה שנראה בתוך המסגרת משתנה.'
                 : 'Drag the photo. Nothing is stretched — this only picks the part that shows.',
        cta: cr.isNew ? (he ? 'הוספת התמונה' : 'Add this photo') : (he ? 'שמירה' : 'Save'),
        bg: Math.round(cr.x) + '% ' + Math.round(cr.y) + '%/cover no-repeat url("' + cr.src + '")',
        down: e => this.epCropDown(e),
        save: () => this.epCropSave(),
        cancel: () => this.setState({ epCrop: null })
      };

      // the sheet for one item
"@
Swap $oldSheet $newSheet 'crop model'

# 6 - and a way back to it from a photo already on the profile
$oldActions = "              <div class=`"eps-actions`">`n                <button class=`"eps-btn tg-tap`" sc-camel-on-click=`"{{ ep.sheet.replace }}`">"
$newActions = "              <div class=`"eps-actions`">`n" +
  "                <sc-if value=`"{{ ep.sheet.isPhoto }}`">`n" +
  "                  <button class=`"eps-btn tg-tap`" sc-camel-on-click=`"{{ ep.sheet.reframe }}`"><svg width=`"18`" height=`"18`" sc-camel-view-box=`"0 0 24 24`" fill=`"none`" stroke=`"currentColor`" stroke-width=`"1.9`" stroke-linecap=`"round`"><path d=`"M8 3v4a1 1 0 0 1-1 1H3`"></path><path d=`"M16 21v-4a1 1 0 0 1 1-1h4`"></path><rect x=`"3`" y=`"3`" width=`"18`" height=`"18`" rx=`"3`"></rect></svg>Reframe</button>`n" +
  "                </sc-if>`n" +
  "                <button class=`"eps-btn tg-tap`" sc-camel-on-click=`"{{ ep.sheet.replace }}`">"
Swap $oldActions $newActions 'reframe button'

$oldReplace = "        replaceLabel: sk === 'video' ? (he ? 'החלפת סרטון' : 'Replace video') : (he ? 'החלפת תמונה' : 'Replace photo'),"
$newReplace = $oldReplace + "`n        reframe: () => { if (cur && cur.src) { this.setState({ epSheet: null }); this.epCropOpen(cur.src, false); } },"
Swap $oldReplace $newReplace 'reframe handler'

# 7 - the sheet itself, sitting above the item sheet
$oldOpen = "        <sc-if value=`"{{ ep.sheet.open }}`" hint-placeholder-val=`"{{ false }}`">"
$newOpen = @"
        <sc-if value="{{ ep.crop.open }}" hint-placeholder-val="{{ false }}">
          <div class="eps-scrim" sc-camel-on-click="{{ ep.crop.cancel }}"></div>
          <div class="eps epc">
            <div class="eps-grab"></div>
            <div class="eps-head"><span class="eps-title">{{ ep.crop.title }}</span></div>
            <div class="epc-frame" sc-camel-on-pointer-down="{{ ep.crop.down }}" style="background:{{ ep.crop.bg }}">
              <i class="epc-v1"></i><i class="epc-v2"></i><i class="epc-h1"></i><i class="epc-h2"></i>
            </div>
            <p class="epc-hint">{{ ep.crop.hint }}</p>
            <button class="btn btn-primary btn-block tg-tap" style="height:50px" sc-camel-on-click="{{ ep.crop.save }}">{{ ep.crop.cta }}</button>
            <button class="btn btn-secondary btn-block tg-tap" style="height:46px" sc-camel-on-click="{{ ep.crop.cancel }}">Cancel</button>
          </div>
        </sc-if>

$oldOpen
"@
Swap $oldOpen $newOpen 'crop markup'

# 8 - its look: the real frame, a grabbable picture, thirds to aim with
$css = '<style>' +
  '.epc{padding-bottom:calc(var(--space-6) + env(safe-area-inset-bottom))}' +
  '.epc-frame{position:relative;width:100%;aspect-ratio:3/4.15;max-height:46vh;margin:2px auto 0;border-radius:18px;' +
  'overflow:hidden;touch-action:none;cursor:grab;background-color:#140D14;' +
  'box-shadow:inset 0 0 0 1px rgba(255,255,255,.14),0 20px 44px -22px #000}' +
  '.epc-frame:active{cursor:grabbing}' +
  '.epc-frame i{position:absolute;background:rgba(255,255,255,.22);pointer-events:none}' +
  '.epc-frame .epc-v1,.epc-frame .epc-v2{top:0;bottom:0;width:1px}' +
  '.epc-frame .epc-v1{left:33.33%}.epc-frame .epc-v2{left:66.66%}' +
  '.epc-frame .epc-h1,.epc-frame .epc-h2{left:0;right:0;height:1px}' +
  '.epc-frame .epc-h1{top:33.33%}.epc-frame .epc-h2{top:66.66%}' +
  '.epc-hint{margin:14px 2px 16px;font-size:13px;line-height:1.5;color:rgba(242,234,230,.62);text-wrap:pretty}' +
  '</style>'
$h = $raw.IndexOf('</helmet>')
if ($h -lt 0) { throw 'crop: no helmet' }
$raw = $raw.Substring(0, $h) + $css + $raw.Substring($h)
$n++

[System.IO.File]::WriteAllText($f, $raw, [System.Text.UTF8Encoding]::new($false))
Write-Output ("crop picker: {0} edits applied" -f $n)
