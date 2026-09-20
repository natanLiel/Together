param([string]$List)
# List lines: <asset-name> <result url>
$scratch = $PSScriptRoot
$assets = "$(Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)\assets\people"
Add-Type -AssemblyName System.Drawing
$enc = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
$ep = New-Object System.Drawing.Imaging.EncoderParameters(1)
$ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]84)
foreach ($line in ($List -split "`n")) {
  $parts = $line.Trim() -split '\s+'
  if ($parts.Count -lt 2) { continue }
  $name = $parts[0]; $url = $parts[1]
  $raw = "$scratch\raw-$name.png"
  & curl.exe -s -o $raw $url
  if (-not (Test-Path $raw) -or (Get-Item $raw).Length -lt 10000) { Write-Output "$name download failed"; continue }
  $im = [System.Drawing.Image]::FromFile($raw)
  $w = $im.Width; $h = $im.Height; $x = 0; $y = 0
  if ($w / $h -gt 0.75) { $nw = $h * 0.75; $x = ($w - $nw) / 2; $w = $nw } else { $nh = $w / 0.75; $y = ($h - $nh) / 2; $h = $nh }
  $bmp = New-Object System.Drawing.Bitmap(720, 960)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode = 'HighQualityBicubic'; $g.PixelOffsetMode = 'HighQuality'
  $g.DrawImage($im, (New-Object System.Drawing.RectangleF(0, 0, 720, 960)), (New-Object System.Drawing.RectangleF([single]$x, [single]$y, [single]$w, [single]$h)), [System.Drawing.GraphicsUnit]::Pixel)
  $g.Dispose(); $im.Dispose()
  $bmp.Save("$assets\$name.jpg", $enc, $ep); $bmp.Dispose()
  Write-Output ("{0}.jpg {1} KB" -f $name, [math]::Round((Get-Item "$assets\$name.jpg").Length / 1KB))
}
