$ErrorActionPreference = 'Stop'

# -- the six women become the six from the folders ---------------------------
#  Photos and the name only. Everything else about each profile -- age, city,
#  prompts, tags, voice notes -- stays where it was, so the writing still
#  reads. Folders were matched to people by how many photos each had, so
#  nobody ends up with an empty frame or a photo left unused.
#
#  The names, including the Hebrew, live in people-map.json rather than here:
#  a .ps1 without a BOM is read as ANSI by Windows PowerShell and Hebrew in it
#  arrives as mojibake. JSON read with an explicit encoding does not care.

$repo = Split-Path $PSScriptRoot -Parent
$mapPath = Join-Path $PSScriptRoot 'people-map.json'
$people = ConvertFrom-Json ([System.IO.File]::ReadAllText($mapPath, [System.Text.UTF8Encoding]::new($false)))

# Only the built template. The Design Component source carries an older,
# smaller cast (no Avigail, no Tamar, no Roni -- build.ps1 adds those), and it
# is in any case still behind the work-PC commits, so editing it here would
# write the swap into a file nobody can rebuild from yet.
$files = @(
  (Join-Path $repo 'build\parts\app-template.cloud.dc.html')
)

foreach ($f in $files) {
  if (-not (Test-Path $f)) { throw "missing $f" }
  $raw = [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8)
  $label = Split-Path $f -Leaf
  Write-Output ("-- " + $label)

  foreach ($p in $people) {
    # 1 - the photo list, and the count behind the "3 / 6" counter
    $pat = "n:\d+, pics:\['assets/people/" + $p.oldKey + "-[^\]]*\]"
    $m = [regex]::Match($raw, $pat)
    if (-not $m.Success) { throw ($label + " : no pics array for " + $p.oldKey) }
    $list = (1..$p.count | ForEach-Object { "'assets/people/" + $p.newKey + "-" + $_ + ".jpg'" }) -join ','
    $raw = $raw.Replace($m.Value, "n:" + $p.count + ", pics:[" + $list + "]")

    # 1b - a photo is also pulled in by hand here and there (the waiting
    #      screen's avatar, for one). Point those at her too, never past the
    #      end of her own set.
    $cnt = $p.count
    $key = $p.newKey
    $raw = [regex]::Replace($raw, "assets/people/" + $p.oldKey + "-(\d+)\.jpg", {
      param($m)
      $n = [int]$m.Groups[1].Value
      if ($n -gt $cnt) { $n = $cnt }
      "assets/people/" + $key + "-" + $n + ".jpg"
    })

    # 2 - a video poster now shows her own face, not the person she replaced
    $i = 0
    foreach ($poster in $p.posters) {
      $vm = [regex]::Match($raw, "src:'assets/people/" + $p.oldKey + "-v\d+\.jpg'")
      if (-not $vm.Success) { break }
      $raw = $raw.Replace($vm.Value, "src:'assets/people/" + $poster + "'")
      $i++
    }

    # 3 - the name, the lookup keys (palette, about, likes) and the Hebrew
    $raw = $raw.Replace("name:'" + $p.oldName + "'", "name:'" + $p.newName + "'")
    $raw = $raw.Replace($p.oldKey + ":", $p.newKey + ":")
    $raw = $raw.Replace("'" + $p.oldKey + "'", "'" + $p.newKey + "'")
    $raw = $raw.Replace($p.oldName, $p.newName)
    $raw = $raw.Replace($p.oldHe, $p.newHe)

    Write-Output ("   {0,-8} -> {1,-7} {2} photos, {3} video poster(s)" -f $p.oldName, $p.newName, $p.count, $i)
  }

  foreach ($p in $people) {
    if ($raw.Contains("assets/people/" + $p.oldKey + "-")) { throw ($label + " : " + $p.oldKey + " photos still referenced") }
    if ($raw.Contains($p.oldName)) { throw ($label + " : the name " + $p.oldName + " is still in the file") }
  }
  [System.IO.File]::WriteAllText($f, $raw, [System.Text.UTF8Encoding]::new($false))
}
Write-Output 'done'
