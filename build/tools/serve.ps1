$root = "$(Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:5731/")
$listener.Prefixes.Add("http://127.0.0.1:5731/")
$listener.Start()
Write-Host "Listening on http://localhost:5731/"
$mime = @{ ".html"="text/html; charset=utf-8"; ".json"="application/json"; ".png"="image/png"; ".svg"="image/svg+xml"; ".js"="application/javascript" }
while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $req = $ctx.Request
    $res = $ctx.Response
    $path = $req.Url.LocalPath
    if ($path -eq "/") { $path = "/index.html" }
    $file = Join-Path $root ($path.TrimStart("/"))
    if (Test-Path $file -PathType Leaf) {
        $ext = [System.IO.Path]::GetExtension($file)
        $ct = $mime[$ext]
        if (-not $ct) { $ct = "application/octet-stream" }
        $res.ContentType = $ct
        $bytes = [System.IO.File]::ReadAllBytes($file)
        $res.ContentLength64 = $bytes.Length
        $res.OutputStream.Write($bytes, 0, $bytes.Length)
    } else {
        $res.StatusCode = 404
    }
    $res.OutputStream.Close()
}
