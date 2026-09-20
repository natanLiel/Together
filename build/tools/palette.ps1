Add-Type -AssemblyName System.Drawing
$dir = "$(Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)\assets\people"

function Hsl($c) { return @($c.GetHue(), $c.GetSaturation(), $c.GetBrightness()) }
function HslToHex([double]$h, [double]$s, [double]$l) {
  $h = (($h % 360) + 360) % 360 / 360
  $q = if ($l -lt 0.5) { $l * (1 + $s) } else { $l + $s - $l * $s }
  $p = 2 * $l - $q
  $f = { param($t) if ($t -lt 0) { $t += 1 }; if ($t -gt 1) { $t -= 1 }
    if ($t -lt 1/6) { return $p + ($q - $p) * 6 * $t }
    if ($t -lt 1/2) { return $q }
    if ($t -lt 2/3) { return $p + ($q - $p) * (2/3 - $t) * 6 }
    return $p }
  $r = [int][math]::Round((& $f ($h + 1/3)) * 255); $g = [int][math]::Round((& $f $h) * 255); $b = [int][math]::Round((& $f ($h - 1/3)) * 255)
  return ('#{0:X2}{1:X2}{2:X2}' -f $r, $g, $b)
}

$out = [ordered]@{}
Get-ChildItem $dir -Filter '*-1.jpg' | Sort-Object Name | ForEach-Object {
  $name = $_.BaseName -replace '-1$', ''
  $src = [System.Drawing.Image]::FromFile($_.FullName)
  $bmp = New-Object System.Drawing.Bitmap(30, 38)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode = 'HighQualityBicubic'
  $g.DrawImage($src, 0, 0, 30, 38); $g.Dispose(); $src.Dispose()
  $px = @()
  for ($y = 0; $y -lt 38; $y++) { for ($x = 0; $x -lt 30; $x++) {
    $c = $bmp.GetPixel($x, $y); $hs = Hsl $c
    $score = $hs[1] * (1 - [math]::Abs($hs[2] - 0.5) * 2)
    if ($hs[0] -ge 8 -and $hs[0] -le 50) { $score *= 0.22 }   # skin and warm shadows: every face has them
    $px += ,@($score, $hs[0], $hs[1], $hs[2])
  } }
  $bmp.Dispose()
  $top = $px | Sort-Object { $_[0] } -Descending | Select-Object -First ([int]($px.Count * 0.18))
  # circular mean of hue, weighted by score
  $sx = 0; $sy = 0; $ss = 0; $w = 0
  foreach ($p in $top) { $a = $p[1] * [math]::PI / 180; $sx += [math]::Cos($a) * $p[0]; $sy += [math]::Sin($a) * $p[0]; $ss += $p[2] * $p[0]; $w += $p[0] }
  $hue = [math]::Atan2($sy, $sx) * 180 / [math]::PI
  $sat = if ($w) { $ss / $w } else { 0.3 }
  # a few photos read better by eye than by average: studio dark, office cool, library green
  $over = @{ shira = @(252, 0.42); tamar = @(168, 0.34); eitan = @(100, 0.36); itai = @(36, 0.5) }
  if ($over.ContainsKey($name)) { $hue = $over[$name][0]; $sat = $over[$name][1] }
  $vs = [math]::Min(0.72, [math]::Max(0.34, $sat))
  $out[$name] = @{
    v = HslToHex $hue $vs 0.5
    d = HslToHex $hue ([math]::Min(0.45, $vs)) 0.17
    l = HslToHex $hue ([math]::Min(0.55, $vs)) 0.9
  }
  "{0,-8} hue {1,6:N1}  sat {2:N2}  v {3}  d {4}  l {5}" -f $name, $hue, $sat, $out[$name].v, $out[$name].d, $out[$name].l
}
$js = ($out.Keys | ForEach-Object { "  {0}: {{ v:'{1}', d:'{2}', l:'{3}' }}" -f $_, $out[$_].v, $out[$_].d, $out[$_].l }) -join ",`n"
[System.IO.File]::WriteAllText("$PSScriptRoot\palette.js.txt", "static PALETTE = {`n" + $js + "`n};", (New-Object System.Text.UTF8Encoding($false)))
