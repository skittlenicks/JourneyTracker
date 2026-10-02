param(
    [string]$OutDir = (Join-Path $PSScriptRoot "..\dist"),
    # Map tiles the page carries. Claude's artifact viewer takes pages up to
    # 16 MB, and base64 makes the tiles a third bigger.
    [double]$TileBudgetMB = 9.5
)
# Builds the recap website draft (sample data) into one self-contained page:
#   dist\road-to-60.html
# It fills recap.template.html with the logo, a sample export string, the map
# art the sample uses, art\maps.json and the web map tiles. The maps come from
# art\export\web (run art\build-maps.ps1 first); they're Blizzard's art, so the
# built page goes to the git-ignored dist\ folder, not the repo.
#
#   powershell -ExecutionPolicy Bypass -File site\build.ps1
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent

function DataUri([string]$mime, [byte[]]$bytes) { return "data:$mime;base64," + [Convert]::ToBase64String($bytes) }

# Logo, shrunk to 192px for the page.
$logo = [System.Drawing.Image]::FromFile((Join-Path $root "art\curseforge-logo.png"))
$small = New-Object System.Drawing.Bitmap 192, 192
$g = [System.Drawing.Graphics]::FromImage($small)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$g.DrawImage($logo, 0, 0, 192, 192)
$g.Dispose(); $logo.Dispose()
$ms = New-Object System.IO.MemoryStream
$small.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)

# The import box shows the round-trip test's export string (fake data).
$export = (Get-Content (Join-Path $root "tools\import\fixtures\testexport.txt") -Encoding UTF8 |
    Where-Object { $_ -like "JT*" } | Select-Object -First 1).Trim()

$html = Get-Content (Join-Path $PSScriptRoot "recap.template.html") -Raw -Encoding UTF8
$html = $html.Replace("__LOGO__", (DataUri "image/png" $ms.ToArray()))
$html = $html.Replace("__SAMPLE_EXPORT__", [System.Net.WebUtility]::HtmlEncode($export))
# Map art: __MAP_<id>__ parchment zone maps and __TERRAIN_<id>__ terrain zone
# maps (from art\build-maps.ps1).
$folders = @{ MAP = "zones"; TERRAIN = "terrain" }
foreach ($match in [regex]::Matches($html, "__(MAP|TERRAIN)_(\d+)__")) {
    $file = Join-Path $root ("art\export\web\{0}\{1}.jpg" -f $folders[$match.Groups[1].Value], $match.Groups[2].Value)
    if (-not (Test-Path $file)) { throw "Missing $file. Run art\build-maps.ps1 first." }
    $html = $html.Replace($match.Value, (DataUri "image/jpeg" ([System.IO.File]::ReadAllBytes($file))))
}

# Map tiles. All ~8,700 won't fit, so the page takes them in this order while
# they do: the whole map out to zoom 7 (where a zone fills the screen, route
# zones first), then closer zooms for the zones with sample hotspots and the
# rest of the route.
$tileRoot = Join-Path $root "art\export\web\tiles"
if (-not (Test-Path $tileRoot)) { throw "Missing $tileRoot. Run art\build-maps.ps1 first." }
$maps = Get-Content (Join-Path $root "art\maps.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$grid = @{}      # continent (0, 1) -> its minimap tiles on the web map
$byName = @{}
foreach ($m in $maps) {
    if ($m.minimap) { $grid[[int]$m.mapID] = $m.minimap }
    if ($m.type -eq 3 -and -not $byName.ContainsKey($m.name)) { $byName[$m.name] = $m }
}
# A zone's rectangle on the web map, in minimap tiles: left, top, right, bottom.
function Get-Box($m) {
    $c = $grid[[int]$m.mapID]; $T = $c.tileYards; $w = $m.world
    return ,@((32 - $w.maxY / $T + $c.layout.x), (32 - $w.maxX / $T + $c.layout.y),
              (32 - $w.minY / $T + $c.layout.x), (32 - $w.minX / $T + $c.layout.y))
}
# The sample's zones, read from the template: its route (S.path) and the
# zones it has hotspots for (S.heat).
$routeBoxes = New-Object System.Collections.ArrayList
$path = [regex]::Match($html, '(?s)\bpath:\s*\[(.*?)\]\s*\]').Groups[1].Value
foreach ($match in [regex]::Matches($path, '"([^"]+)"')) {
    $m = $byName[$match.Groups[1].Value]
    if ($m -and $m.world -and $grid.ContainsKey([int]$m.mapID)) { [void]$routeBoxes.Add((Get-Box $m)) }
}
$hotBoxes = New-Object System.Collections.ArrayList
foreach ($match in [regex]::Matches($html, '\bzone:\s*"[^"]+",\s*map:\s*(\d+)')) {
    $m = $maps | Where-Object { $_.uiMapID -eq [int]$match.Groups[1].Value } | Select-Object -First 1
    if ($m -and $m.world -and $grid.ContainsKey([int]$m.mapID)) { [void]$hotBoxes.Add((Get-Box $m)) }
}
if ($routeBoxes.Count -eq 0) { throw "Couldn't find the sample route (path: [...]) in recap.template.html." }
function Test-Touch($boxes, [double]$l, [double]$t, [double]$r, [double]$b) {
    foreach ($box in $boxes) { if ($l -lt $box[2] -and $r -gt $box[0] -and $t -lt $box[3] -and $b -gt $box[1]) { return $true } }
    return $false
}
$tiles = foreach ($f in Get-ChildItem -Path $tileRoot -Recurse -File -Filter "*.jpg") {
    $z = [int]$f.Directory.Parent.Name; $x = [int]$f.Directory.Name; $y = [int]$f.BaseName
    $span = [math]::Pow(2, 8 - $z)   # minimap tiles across one web tile
    $l = $x * $span; $t = $y * $span
    [pscustomobject]@{ key = "$z/$x/$y"; z = $z; file = $f.FullName; bytes = $f.Length
        route = (Test-Touch $routeBoxes $l $t ($l + $span) ($t + $span))
        hot = (Test-Touch $hotBoxes $l $t ($l + $span) ($t + $span)) }
}
$groups = @(
    @{ name = "whole map, zoom 3-6"; pick = { $_.z -le 6 } },
    @{ name = "route zones, zoom 7"; pick = { $_.z -eq 7 -and $_.route } },
    @{ name = "rest of map, zoom 7"; pick = { $_.z -eq 7 -and -not $_.route } },
    @{ name = "hotspot zones, zoom 8"; pick = { $_.z -eq 8 -and $_.hot } },
    @{ name = "rest of route, zoom 8"; pick = { $_.z -eq 8 -and $_.route -and -not $_.hot } },
    @{ name = "hotspot zones, zoom 9"; pick = { $_.z -eq 9 -and $_.hot } },
    @{ name = "rest of route, zoom 9"; pick = { $_.z -eq 9 -and $_.route -and -not $_.hot } }
)
$budget = $TileBudgetMB * 1MB; $used = 0
$chosen = New-Object System.Collections.ArrayList
foreach ($group in $groups) {
    $set = @($tiles | Where-Object $group.pick)
    $bytes = ($set | Measure-Object bytes -Sum).Sum
    $fits = $used + $bytes -le $budget
    if ($fits) { $chosen.AddRange($set); $used += $bytes }
    Write-Host ("  {0,-22} {1,5} tiles {2,7:N0} KB  {3}" -f $group.name, $set.Count, ($bytes / 1KB), $(if ($fits) { "in" } else { "left out" }))
}
$sb = New-Object System.Text.StringBuilder
[void]$sb.Append("{")
for ($i = 0; $i -lt $chosen.Count; $i++) {
    if ($i) { [void]$sb.Append(",`n") }
    [void]$sb.Append('"').Append($chosen[$i].key).Append('":"')
    [void]$sb.Append((DataUri "image/jpeg" ([System.IO.File]::ReadAllBytes($chosen[$i].file)))).Append('"')
}
[void]$sb.Append("}")
$html = $html.Replace("__TILES__", $sb.ToString())
# Every zoom-8 tile of the full map (one per minimap tile), carried or not,
# so the page can tell open sea from map it doesn't carry.
$land = $tiles | Where-Object { $_.z -eq 8 } | ForEach-Object { '"' + $_.key.Substring(2) + '"' }
$html = $html.Replace("__TILE_LAND__", "[" + ($land -join ",") + "]")

# Every map's world rectangle and place on the web map, so heat lands in the right place.
$html = $html.Replace("__MAPS_JSON__", (Get-Content (Join-Path $root "art\maps.json") -Raw -Encoding UTF8).Trim())
# Leaflet's stylesheet has to be inside the page (its script loads from cdnjs).
$leaflet = Get-Content (Join-Path $PSScriptRoot "vendor\leaflet-1.9.4.css") -Raw -Encoding UTF8
$html = $html.Replace("/*__LEAFLET_CSS__*/", "/* Leaflet 1.9.4, https://leafletjs.com, (c) 2010-2023 Vladimir Agafonkin, (c) 2010-2011 CloudMade. BSD-2-Clause. */`n" + $leaflet.Trim())
# The rankings catalog, shared with the finished site.
$rankings = Get-Content (Join-Path $PSScriptRoot "rankings.js") -Raw -Encoding UTF8
$html = $html.Replace("/*__RANKINGS__*/", $rankings.Trim())

New-Item -ItemType Directory -Force $OutDir | Out-Null
$out = Join-Path (Resolve-Path $OutDir) "road-to-60.html"
[System.IO.File]::WriteAllText($out, $html, (New-Object System.Text.UTF8Encoding $false))
Write-Host ("Built {0} ({1:N0} KB, {2:N0} map tiles)" -f $out, ((Get-Item $out).Length / 1KB), $chosen.Count)
