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
$thumb = '<div id="__bundler_thumbnail"><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400">' +
  '<rect width="400" height="400" fill="#F9F1E9"></rect>' +
  '<g transform="translate(200 200) scale(0.5) translate(-252.2 -132.8)" fill="none" stroke-width="25.6">' +
  '<circle cx="182.8" cy="132.8" r="100" stroke="#2A3F6E"></circle>' +
  '<circle cx="321.6" cy="132.8" r="100" stroke="#E4485B"></circle></g></svg></div>'
$doc = [regex]::Replace($doc, '<div id="__bundler_thumbnail">.*?</div>', $thumb)
$doc = $doc.Replace('background: #faf9f5;', 'background: #F9F1E9;')
$doc = $doc.Replace('<title>Bundled Page</title>', '<title>Together</title>')
$doc = $doc.Replace('background: #E3E1D8;', 'background: #F9F1E9;')

# re-attach the bar layer (replacing any previous copy)
$dock = [System.IO.File]::ReadAllText("$scratch\dockscript.html", [System.Text.Encoding]::UTF8)
$doc = [regex]::Replace($doc, '(?s)\r?\n<script>\r?\n/\* .. Together . the one-mark bar.*?</script>', '')
$last = $doc.LastIndexOf('</body>')
if ($last -lt 0) { throw "no </body> in index.html" }
$doc = $doc.Substring(0, $last) + $dock.TrimEnd() + "`n" + $doc.Substring($last)

[System.IO.File]::WriteAllText("$repo\index.html", $doc, $utf8)

Write-Output ("index.html rebuilt from your source: {0} KB" -f [math]::Round((Get-Item "$repo\index.html").Length/1KB,1))
