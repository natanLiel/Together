$ErrorActionPreference = "Stop"
$scratch = Join-Path $PSScriptRoot "parts"
$repo    = Split-Path $PSScriptRoot -Parent
$utf8    = New-Object System.Text.UTF8Encoding($false)

$tpl = [System.IO.File]::ReadAllText("$scratch\app-template.rebuilt.dc.html", [System.Text.Encoding]::UTF8)

$json = ConvertTo-Json -InputObject $tpl -Compress
if ($json -match '</script>') { throw "re-encoded template contains a literal </script>" }

$idx = [System.IO.File]::ReadAllLines("$repo\index.html", [System.Text.Encoding]::UTF8)
$head382 = $idx[381].Substring(0, [Math]::Min(70, $idx[381].Length))
if (-not ($idx[381].StartsWith('"') -and $head382 -match 'DOCTYPE html')) {
    throw "line 382 is not the bundler template string: $head382"
}
$idx[381] = $json
$doc = $idx -join "`n"

# the unpacking thumbnail shows the new mark on the stock ground
$markSvg = '<defs>' +
  '<linearGradient id="ta" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FF7488"/><stop offset="1" stop-color="#E4485B"/></linearGradient>' +
  '<linearGradient id="tb" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#C7D4F2"/><stop offset="1" stop-color="#7B93DC"/></linearGradient>' +
  '<mask id="tm"><rect x="0" y="0" width="160" height="100" fill="#fff"/>' +
  '<circle cx="98" cy="53" r="31" fill="none" stroke="#000" stroke-width="12.3"/></mask></defs>' +
  '<circle cx="62" cy="47" r="27" fill="none" stroke="url(#ta)" stroke-width="7.5" mask="url(#tm)"/>' +
  '<circle cx="98" cy="53" r="31" fill="none" stroke="url(#tb)" stroke-width="7.5"/>'
$thumb = '<div id="__bundler_thumbnail"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400">' +
  '<rect width="400" height="400" rx="92" fill="#171018"></rect>' +
  '<g transform="translate(200 200) scale(1.9) translate(-80 -50)">' + $markSvg + '</g></svg></div>'
$favSvg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 160 100">' + $markSvg + '</svg>'
$tileSvg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">' +
  '<rect width="512" height="512" rx="118" fill="#171018"></rect>' +
  '<g transform="translate(256 256) scale(2.4) translate(-80 -50)">' + $markSvg + '</g></svg>'
$favUri = 'data:image/svg+xml;charset=utf-8,' + [uri]::EscapeDataString($favSvg)
$tileUri = 'data:image/svg+xml;charset=utf-8,' + [uri]::EscapeDataString($tileSvg)
$doc = [regex]::Replace($doc, '<div id="__bundler_thumbnail">.*?</div>', $thumb)
$doc = $doc.Replace('background: #faf9f5;', 'background: #120C12;')
$doc = $doc.Replace('<title>Bundled Page</title>', '<title>Together</title>')
# drop any icons a previous run left, so this stays repeatable
$doc = [regex]::Replace($doc, '<link rel="(?:icon|apple-touch-icon)"[^>]*?data:image/svg\+xml[^>]*?>', '')
$doc = $doc.Replace('<title>Together</title>', '<title>Together</title>' +
  '<link rel="icon" href="' + $favUri + '">' +
  '<link rel="apple-touch-icon" sizes="512x512" href="' + $tileUri + '">')
$doc = $doc.Replace('background: #E3E1D8;', 'background: #120C12;')

# re-attach the bar layer (replacing any previous copy)
$dock = [System.IO.File]::ReadAllText("$scratch\dockscript.html", [System.Text.Encoding]::UTF8)
$doc = [regex]::Replace($doc, '(?s)\r?\n<script>\r?\n/\* .. Together . the one-mark bar.*?</script>', '')
$last = $doc.LastIndexOf('</body>')
if ($last -lt 0) { throw "no </body> in index.html" }
$doc = $doc.Substring(0, $last) + $dock.TrimEnd() + "`n" + $doc.Substring($last)

[System.IO.File]::WriteAllText("$repo\index.html", $doc, $utf8)

Write-Output ("index.html rebuilt from your source: {0} KB" -f [math]::Round((Get-Item "$repo\index.html").Length/1KB,1))
