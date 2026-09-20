$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
$repo = $(Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)

# Same geometry as mark.svg: r 100, stroke 25.6, centres 138.8 apart.
# The interlock is painted with ground-coloured gaps here, which is safe
# because an app icon always sits on its own opaque tile.
function Render([int]$size, [string]$out) {
    $S = 1024
    $bmp = New-Object System.Drawing.Bitmap($S, $S)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

    $stock = [System.Drawing.ColorTranslator]::FromHtml("#E3E1D8")
    $blue  = [System.Drawing.ColorTranslator]::FromHtml("#2A3F6E")
    $rose  = [System.Drawing.ColorTranslator]::FromHtml("#E4485B")
    $g.Clear($stock)

    # fit the 504.4 x 265.6 mark into the middle ~60% of the tile (inside the
    # maskable safe zone)
    $k  = ($S * 0.64) / 504.4
    $ox = ($S - 504.4 * $k) / 2
    $oy = ($S - 265.6 * $k) / 2
    $r  = 100 * $k
    $w  = 36 * $k      # heavier than the in-app 25.6: optical weight for ~60px
    $gap = 16 * $k

    function Rect($cx, $cy) {
        New-Object System.Drawing.RectangleF(($ox + ($cx - 100) * $k), ($oy + ($cy - 100) * $k), (2 * $r), (2 * $r))
    }
    $L = Rect 182.8 132.8
    $R = Rect 321.6 132.8

    function Pen($c, $wd) {
        $p = New-Object System.Drawing.Pen($c, $wd)
        $p.StartCap = [System.Drawing.Drawing2D.LineCap]::Flat
        $p.EndCap   = [System.Drawing.Drawing2D.LineCap]::Flat
        return $p
    }
    $pBlue = Pen $blue $w
    $pRose = Pen $rose $w
    $pCut  = Pen $stock ($w + $gap)

    $g.DrawEllipse($pBlue, $L)                 # ink one, whole
    $g.DrawArc($pCut, $R, 116, 36)             # gap where ink two will pass over it (bottom)
    $g.DrawEllipse($pRose, $R)                 # ink two, whole
    $g.DrawArc($pCut, $L, -64, 36)             # gap where ink one passes over it (top)
    $g.DrawArc($pBlue, $L, -64, 36)            # ink one, back over the top crossing

    $g.Dispose()

    $final = New-Object System.Drawing.Bitmap($size, $size)
    $g2 = [System.Drawing.Graphics]::FromImage($final)
    $g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g2.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g2.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g2.DrawImage($bmp, 0, 0, $size, $size)
    $g2.Dispose(); $bmp.Dispose()
    $final.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
    $final.Dispose()
    Write-Output ("{0}: {1}x{1}, {2} KB" -f (Split-Path $out -Leaf), $size, [math]::Round((Get-Item $out).Length/1KB,1))
}

Render 512 "$repo\app-icon.png"
Render 180 "$repo\apple-touch-icon.png"

# the installed app launches on the stock ground, not the old plum-black
$mf = "$repo\manifest.json"
$m = [System.IO.File]::ReadAllText($mf, [System.Text.Encoding]::UTF8)
$m = $m.Replace('"background_color": "#14101A"', '"background_color": "#E3E1D8"')
$m = $m.Replace('"theme_color": "#14101A"', '"theme_color": "#E3E1D8"')
$m = $m.Replace('"sizes": "512x512",
      "type": "image/png",
      "purpose": "maskable"', '"sizes": "512x512",
      "type": "image/png",
      "purpose": "maskable"')
[System.IO.File]::WriteAllText($mf, $m, (New-Object System.Text.UTF8Encoding($false)))
Write-Output "manifest colours updated"
