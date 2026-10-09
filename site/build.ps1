param(
    [string]$OutDir = (Join-Path $PSScriptRoot "..\dist"),
    # Build the website instead: a page that loads its map art as files, for
    # site\deploy.ps1 to put online.
    [switch]$Site
)
# Builds the recap website draft (sample data). By default it's one
# self-contained page for Claude's artifact viewer:
#   dist\road-to-60.html
# With -Site it's the website:
#   dist\site\index.html, favicon.png, og.png (its link preview),
#   download\JourneyTracker-<version>.zip (the addon),
#   worldmap\<UiMapID>.jpg (the world and both continents),
#   worldmap\highlights\<UiMapID>.jpg (each zone's glow) and
#   zones\<UiMapID>.jpg (each zone's map)
# It fills recap.template.html with the logo, the map art, art\maps.json,
# art\worldmap.json, art\dungeons.json, the rankings catalog and the journey
# model. The art is the game's: run art\build-maps.ps1, art\worldmap.js and
# art\dungeons.js first. It's
# Blizzard's, so the build goes to the git-ignored dist\ folder, not the
# repo. The website build needs Node.js, for og.png.
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

# The map art, by the name the page asks for: the world, the continents and
# each zone's glow (PNGs from art\worldmap.js, made JPEG here) and each
# zone's own map (art\build-maps.ps1).
$jpeg = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq "image/jpeg" }
function Get-ArtBytes($source) {
    if ($source.jpg) {
        if (-not (Test-Path $source.jpg)) { throw "Missing $($source.jpg). Run art\build-maps.ps1 first." }
        return ,[System.IO.File]::ReadAllBytes($source.jpg)
    }
    if (-not (Test-Path $source.png)) { throw "Missing $($source.png). Run art\worldmap.js first (see its header)." }
    $img = [System.Drawing.Image]::FromFile($source.png)
    $out = New-Object System.IO.MemoryStream
    try {
        $params = New-Object System.Drawing.Imaging.EncoderParameters 1
        $params.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), ([long]$source.quality)
        $img.Save($out, $jpeg, $params)
    } finally { $img.Dispose() }
    return ,$out.ToArray()
}
$worldmapDir = Join-Path $root "art\export\worldmap"
$worldmap = Get-Content (Join-Path $root "art\worldmap.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$maps = Get-Content (Join-Path $root "art\maps.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$art = [ordered]@{}
foreach ($id in $worldmap.art) { $art["worldmap/$id.jpg"] = @{ png = (Join-Path $worldmapDir "$id.png"); quality = 88 } }
foreach ($zone in $worldmap.zones.PSObject.Properties) {
    $art["worldmap/highlights/$($zone.Name).jpg"] = @{ png = (Join-Path $worldmapDir "highlights\$($zone.Name).png"); quality = 92 }
}
# And each continent's outline on the world map.
foreach ($id in $worldmap.outlines) { $art["worldmap/highlights/$id.jpg"] = @{ png = (Join-Path $worldmapDir "highlights\$id.png"); quality = 92 } }
foreach ($m in $maps) { if ($m.image) { $art[$m.image] = @{ jpg = (Join-Path $root "art\export\web\$($m.image)") } } }

if ($Site) {
    # The website serves the art as files, from the site's root (share pages
    # live at /j/<id>).
    $html = $html.Replace("__ART__", "{}").Replace("__ART_ROOT__", '"/"')
} else {
    # The one-file page carries the world, the continents, every glow and the
    # maps of the sample's own zones (its route and its hotspots).
    $byName = @{}
    foreach ($m in $maps) { if ($m.type -eq 3 -and -not $byName.ContainsKey($m.name)) { $byName[$m.name] = $m } }
    $wanted = @{}
    $path = [regex]::Match($html, '(?s)\bpath:\s*\[(.*?)\]\s*\]').Groups[1].Value
    foreach ($match in [regex]::Matches($path, '"([^"]+)"')) {
        $m = $byName[$match.Groups[1].Value]
        if ($m -and $m.image) { $wanted[$m.image] = $true }
    }
    foreach ($match in [regex]::Matches($html, '\bzone:\s*"[^"]+",\s*map:\s*(\d+)')) { $wanted["zones/$($match.Groups[1].Value).jpg"] = $true }
    if ($wanted.Count -eq 0) { throw "Couldn't find the sample route (path: [...]) in recap.template.html." }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("{")
    $carried = 0
    foreach ($name in $art.Keys) {
        if ($name.StartsWith("zones/") -and -not $wanted.ContainsKey($name)) { continue }
        if ($carried) { [void]$sb.Append(",`n") }
        [void]$sb.Append('"').Append($name).Append('":"').Append((DataUri "image/jpeg" (Get-ArtBytes $art[$name]))).Append('"')
        $carried++
    }
    [void]$sb.Append("}")
    $html = $html.Replace("__ART__", $sb.ToString()).Replace("__ART_ROOT__", "null")
}

# Every map's place in the world, and where each zone's glow is centered.
$html = $html.Replace("__MAPS_JSON__", (Get-Content (Join-Path $root "art\maps.json") -Raw -Encoding UTF8).Trim())
$html = $html.Replace("__WORLDMAP_JSON__", (Get-Content (Join-Path $root "art\worldmap.json") -Raw -Encoding UTF8).Trim())
# Each dungeon's entrance, for the route's stops in them (art\dungeons.js).
$html = $html.Replace("__DUNGEONS_JSON__", (Get-Content (Join-Path $root "art\dungeons.json") -Raw -Encoding UTF8).Trim())
# The rankings catalog and the journey model, shared with the site's functions.
$rankings = Get-Content (Join-Path $PSScriptRoot "rankings.js") -Raw -Encoding UTF8
$html = $html.Replace("/*__RANKINGS__*/", $rankings.Trim())
$model = Get-Content (Join-Path $PSScriptRoot "model.js") -Raw -Encoding UTF8
$html = $html.Replace("/*__MODEL__*/", $model.Trim())

$utf8 = New-Object System.Text.UTF8Encoding $false
New-Item -ItemType Directory -Force $OutDir | Out-Null
if ($Site) {
    $siteDir = Join-Path (Resolve-Path $OutDir) "site"
    New-Item -ItemType Directory -Force $siteDir | Out-Null

    # The addon to download: the JourneyTracker folder as it goes in AddOns,
    # zipped with forward slashes so every unzipper makes the folders.
    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $addon = Join-Path $root "JourneyTracker"
    $version = [regex]::Match((Get-Content (Join-Path $addon "JourneyTracker.toc") -Raw), "(?m)^## Version:\s*(\S+)").Groups[1].Value
    if (-not $version) { throw "No ## Version line in JourneyTracker.toc." }
    $zipName = "JourneyTracker-$version.zip"
    $downloadDir = Join-Path $siteDir "download"
    New-Item -ItemType Directory -Force $downloadDir | Out-Null
    Get-ChildItem $downloadDir -File | Where-Object { $_.Name -ne $zipName } | ForEach-Object { $_.Delete() }
    $stream = [System.IO.File]::Open((Join-Path $downloadDir $zipName), [System.IO.FileMode]::Create)
    $zip = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Create)
    foreach ($file in Get-ChildItem $addon -Recurse -File) {
        $entry = "JourneyTracker/" + $file.FullName.Substring($addon.Length + 1).Replace("\", "/")
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file.FullName, $entry,
            [System.IO.Compression.CompressionLevel]::Optimal)
    }
    $zip.Dispose(); $stream.Dispose()
    $zipKB = [math]::Ceiling((Get-Item (Join-Path $downloadDir $zipName)).Length / 1KB)
    $html = $html.Replace("<!--DOWNLOAD-->", "").Replace("<!--/DOWNLOAD-->", "").Replace("__DOWNLOAD_HREF__", "/download/$zipName")
    $html = $html.Replace("__ADDON_VERSION__", "v$version").Replace("__DOWNLOAD_SIZE__", "$zipKB KB")

    # What Claude's artifact viewer puts around the template, the website
    # puts there itself: the document, its metadata and a small reset. A
    # share page (site\api\share.js) swaps in its own title, description and
    # preview image and puts its journey where the JT_SHARED marker is.
    $about = "Journey Tracker is a free WoW Forever addon that records your climb from level 1 to 60. " +
        "Paste its export for a recap: the route across Azeroth, every death and quest, and where you place."
    # Vercel Web Analytics: cookieless page views, counted once it's turned on
    # in the project's Analytics tab (Vercel serves the script from the site
    # itself). The share pages are this page too, so they count as well.
    $analytics = "<script>window.va = window.va || function () { (window.vaq = window.vaq || []).push(arguments); };</script>`n" +
        "<script defer src=`"/_vercel/insights/script.js`"></script>`n"
    $page = "<!doctype html>`n<html lang=`"en`">`n<meta charset=`"utf-8`">`n" +
        "<meta name=`"viewport`" content=`"width=device-width, initial-scale=1`">`n" +
        "<meta name=`"description`" content=`"$about`">`n" +
        "<meta property=`"og:type`" content=`"website`">`n" +
        "<meta property=`"og:site_name`" content=`"Journey Tracker`">`n" +
        "<meta property=`"og:title`" content=`"Road to 60 &middot; Journey Tracker`">`n" +
        "<meta property=`"og:description`" content=`"$about`">`n" +
        "<meta property=`"og:image`" content=`"https://www.journeytracker.dev/og.png`">`n" +
        "<meta property=`"og:image:width`" content=`"1200`">`n" +
        "<meta property=`"og:image:height`" content=`"630`">`n" +
        "<meta property=`"og:image:alt`" content=`"Journey Tracker: your road to 60, recorded by a WoW Forever addon.`">`n" +
        "<meta name=`"twitter:card`" content=`"summary_large_image`">`n" +
        "<meta name=`"theme-color`" content=`"#120e09`">`n" +
        "<link rel=`"icon`" type=`"image/png`" href=`"/favicon.png`">`n" +
        "<style>body { margin: 0; } img { max-width: 100%; } [hidden] { display: none !important; }</style>`n" +
        $analytics + "<!--JT_SHARED-->`n" + $html
    [System.IO.File]::WriteAllText((Join-Path $siteDir "index.html"), $page, $utf8)
    [System.IO.File]::WriteAllBytes((Join-Path $siteDir "favicon.png"), $ms.ToArray())
    # The site's own link preview (site\api\preview.js draws it).
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw "The website build needs Node.js (for og.png)." }
    if (-not (Test-Path (Join-Path $PSScriptRoot "node_modules\@resvg\resvg-wasm"))) {
        npm install --prefix $PSScriptRoot --no-audit --no-fund
        if ($LASTEXITCODE) { throw "npm install in $PSScriptRoot failed." }
    }
    node (Join-Path $PSScriptRoot "api\preview.js") (Join-Path $siteDir "og.png") (Join-Path $siteDir "favicon.png")
    if ($LASTEXITCODE) { throw "Drawing og.png failed." }
    # The map art, every picture the page can ask for. (The minimap tiles an
    # older site used go.)
    foreach ($old in "tiles", "worldmap", "zones") {
        if (Test-Path (Join-Path $siteDir $old)) { [System.IO.Directory]::Delete((Join-Path $siteDir $old), $true) }
    }
    foreach ($name in $art.Keys) {
        $file = Join-Path $siteDir $name.Replace("/", "\")
        New-Item -ItemType Directory -Force (Split-Path $file -Parent) | Out-Null
        [System.IO.File]::WriteAllBytes($file, (Get-ArtBytes $art[$name]))
    }
    Write-Host ("Built {0} ({1:N0} KB page, {2} map pictures, download\{3} {4} KB)" -f $siteDir,
        ((Get-Item (Join-Path $siteDir "index.html")).Length / 1KB), $art.Count, $zipName, $zipKB)
} else {
    # The viewer can't download files, so the one-file page names the site instead.
    $html = [regex]::Replace($html, "<!--DOWNLOAD-->.*?<!--/DOWNLOAD-->",
        { '<p class="download-note">Download it at <b>www.journeytracker.dev</b>.</p>' }, "Singleline")
    $out = Join-Path (Resolve-Path $OutDir) "road-to-60.html"
    [System.IO.File]::WriteAllText($out, $html, $utf8)
    Write-Host ("Built {0} ({1:N0} KB, {2} map pictures)" -f $out, ((Get-Item $out).Length / 1KB), $carried)
}
