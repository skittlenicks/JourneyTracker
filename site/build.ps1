param(
    [string]$OutDir = (Join-Path $PSScriptRoot "..\dist"),
    # Map tiles the one-file page carries. Claude's artifact viewer takes pages
    # up to 16 MB, and base64 makes the tiles a third bigger.
    [double]$TileBudgetMB = 9.5,
    # Build the website instead: a page that loads every map tile as its own
    # file, for site\deploy.ps1 to put online.
    [switch]$Site
)
# Builds the recap website draft (sample data). By default it's one
# self-contained page for Claude's artifact viewer:
#   dist\road-to-60.html
# With -Site it's the website:
#   dist\site\index.html, favicon.png and tiles\<zoom>\<x>\<y>.jpg
# It fills recap.template.html with the logo, the map art the sample uses,
# art\maps.json, the rankings catalog and the web map tiles. The maps come from
# art\export\web (run art\build-maps.ps1 first); they're Blizzard's art, so the
# build goes to the git-ignored dist\ folder, not the repo.
#
#   powershell -ExecutionPolicy Bypass -File site\build.ps1 [-Site]
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

$html = Get-Content (Join-Path $PSScriptRoot "recap.template.html") -Raw -Encoding UTF8
$html = $html.Replace("__LOGO__", (DataUri "image/png" $ms.ToArray()))
# Map art: __MAP_<id>__ parchment zone maps and __TERRAIN_<id>__ terrain zone
# maps (from art\build-maps.ps1).
$folders = @{ MAP = "zones"; TERRAIN = "terrain" }
foreach ($match in [regex]::Matches($html, "__(MAP|TERRAIN)_(\d+)__")) {
    $file = Join-Path $root ("art\export\web\{0}\{1}.jpg" -f $folders[$match.Groups[1].Value], $match.Groups[2].Value)
    if (-not (Test-Path $file)) { throw "Missing $file. Run art\build-maps.ps1 first." }
    $html = $html.Replace($match.Value, (DataUri "image/jpeg" ([System.IO.File]::ReadAllBytes($file))))
}

$tileRoot = Join-Path $root "art\export\web\tiles"
if (-not (Test-Path $tileRoot)) { throw "Missing $tileRoot. Run art\build-maps.ps1 first." }
# Every zoom-8 tile of the full map (one per minimap tile), so the page can
# tell open sea from land.
$land = Get-ChildItem -Path (Join-Path $tileRoot "8") -Recurse -File -Filter "*.jpg" |
    ForEach-Object { '"' + $_.Directory.Name + "/" + $_.BaseName + '"' }
$html = $html.Replace("__TILE_LAND__", "[" + ($land -join ",") + "]")

if ($Site) {
    # The website loads each tile from /tiles as it comes into view (from the
    # site's root, since share pages live at /j/<id>).
    $html = $html.Replace("__TILES__", "{}").Replace("__TILE_ROOT__", '"/tiles/"')
    $tileCount = (Get-ChildItem -Path $tileRoot -Recurse -File -Filter "*.jpg").Count
} else {
    # The one-file page carries its tiles. All ~8,700 won't fit, so it takes
    # them in this order while they do: the whole map out to zoom 7 (where a
    # zone fills the screen, route zones first), then closer zooms for the
    # zones with sample hotspots and the rest of the route.
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
    $html = $html.Replace("__TILES__", $sb.ToString()).Replace("__TILE_ROOT__", "null")
    $tileCount = $chosen.Count
}

# Every map's world rectangle and place on the web map, so heat lands in the right place.
$html = $html.Replace("__MAPS_JSON__", (Get-Content (Join-Path $root "art\maps.json") -Raw -Encoding UTF8).Trim())
# Leaflet's stylesheet has to be inside the page (its script loads from cdnjs).
$leaflet = Get-Content (Join-Path $PSScriptRoot "vendor\leaflet-1.9.4.css") -Raw -Encoding UTF8
$html = $html.Replace("/*__LEAFLET_CSS__*/", "/* Leaflet 1.9.4, https://leafletjs.com, (c) 2010-2023 Vladimir Agafonkin, (c) 2010-2011 CloudMade. BSD-2-Clause. */`n" + $leaflet.Trim())
# The rankings catalog, shared with the finished site.
$rankings = Get-Content (Join-Path $PSScriptRoot "rankings.js") -Raw -Encoding UTF8
$html = $html.Replace("/*__RANKINGS__*/", $rankings.Trim())

$utf8 = New-Object System.Text.UTF8Encoding $false
New-Item -ItemType Directory -Force $OutDir | Out-Null
if ($Site) {
    $siteDir = Join-Path (Resolve-Path $OutDir) "site"
    New-Item -ItemType Directory -Force $siteDir | Out-Null
    # What Claude's artifact viewer puts around the template, the website
    # puts there itself: the document, its metadata and a small reset. A
    # share page (site\api\share.js) swaps in its own title and description
    # and puts its journey where the JT_SHARED marker is.
    $about = "A sample WoW Forever journey from level 1 to 60, as Journey Tracker records it: " +
        "the route across Azeroth, every death and quest, and where it ranks."
    $page = "<!doctype html>`n<html lang=`"en`">`n<meta charset=`"utf-8`">`n" +
        "<meta name=`"viewport`" content=`"width=device-width, initial-scale=1`">`n" +
        "<meta name=`"description`" content=`"$about`">`n" +
        "<meta property=`"og:type`" content=`"website`">`n" +
        "<meta property=`"og:site_name`" content=`"Journey Tracker`">`n" +
        "<meta property=`"og:title`" content=`"Road to 60 &middot; Journey Tracker`">`n" +
        "<meta property=`"og:description`" content=`"$about`">`n" +
        "<meta name=`"twitter:card`" content=`"summary`">`n" +
        "<meta name=`"theme-color`" content=`"#120e09`">`n" +
        "<link rel=`"icon`" type=`"image/png`" href=`"/favicon.png`">`n" +
        "<style>body { margin: 0; } img { max-width: 100%; } [hidden] { display: none !important; }</style>`n" +
        "<!--JT_SHARED-->`n" + $html
    [System.IO.File]::WriteAllText((Join-Path $siteDir "index.html"), $page, $utf8)
    [System.IO.File]::WriteAllBytes((Join-Path $siteDir "favicon.png"), $ms.ToArray())
    # The tiles, copied as they are (robocopy skips ones already there).
    robocopy $tileRoot (Join-Path $siteDir "tiles") *.jpg /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "Copying the map tiles to $siteDir\tiles failed (robocopy exit $LASTEXITCODE)." }
    $global:LASTEXITCODE = 0
    Write-Host ("Built {0} ({1:N0} KB page, {2:N0} map tiles)" -f $siteDir, ((Get-Item (Join-Path $siteDir "index.html")).Length / 1KB), $tileCount)
} else {
    $out = Join-Path (Resolve-Path $OutDir) "road-to-60.html"
    [System.IO.File]::WriteAllText($out, $html, $utf8)
    Write-Host ("Built {0} ({1:N0} KB, {2:N0} map tiles)" -f $out, ((Get-Item $out).Length / 1KB), $tileCount)
}
