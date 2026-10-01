param(
    [string]$ExportDir = (Join-Path $PSScriptRoot "export"),
    [int]$JpegQuality = 85,
    [int]$OverviewTilePixels = 64   # continent overview: pixels per 512px minimap tile
)
# Turns wow.export output into what the website uses:
#   art\export\web\zones\<UiMapID>.jpg      each zone's parchment map, named by the
#                                           game's map ID (the ID the addon records)
#   art\export\web\terrain\<UiMapID>.jpg    the same zone cut from the minimap terrain
#   art\export\web\continents\<UiMapID>.jpg Kalimdor and the Eastern Kingdoms,
#                                           stitched from the minimap terrain
#   art\maps.json                           every map's ID, name, parent, continent,
#                                           world rectangle and images
#
# Input, exported with wow.export from the Forever client (see README):
#   art\export\zones\Zone_<AreaID>_*.png     Zones tab, Show Base Map + Show Overlays
#   art\export\maps\<map>\minimap\mapX_Y.png  Maps tab, Ctrl+A, Export Minimap Tiles
#   art\export\UiMap.csv, UiMapAssignment.csv Data tab, exported as CSV
#
#   powershell -ExecutionPolicy Bypass -File art\build-maps.ps1
#
# Minimap tile mapXX_YY covers world Y (west) from (32 - XX) * T down to
# (31 - XX) * T and world X (north) from (32 - YY) * T down to (31 - YY) * T,
# where T = 533.33 yards (one ADT tile).
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = "Stop"

$uiMaps = Import-Csv -Path (Join-Path $ExportDir "UiMap.csv") -Delimiter ";"
$assignments = Import-Csv -Path (Join-Path $ExportDir "UiMapAssignment.csv") -Delimiter ";"

# Each map's whole-map assignment (UiMin 0,0 to UiMax 1,1) gives its world
# rectangle: Region is minX, minY, minZ, maxX, maxY, maxZ in yards (X north, Y west).
$whole = @{}
foreach ($a in $assignments) {
    if ($a.UiMin -eq "0,0" -and $a.UiMax -eq "1,1" -and -not $whole.ContainsKey($a.UiMapID)) {
        $whole[$a.UiMapID] = $a
    }
}

# Partial assignments place one map inside another: the Azeroth world map
# (947) shows Kalimdor and the Eastern Kingdoms side by side this way.
$parts = @{}
foreach ($a in $assignments) {
    if ($a.UiMin -eq "0,0" -and $a.UiMax -eq "1,1") { continue }
    $lo = $a.UiMin -split "," | ForEach-Object { [double]$_ }
    $hi = $a.UiMax -split "," | ForEach-Object { [double]$_ }
    $r = $a.Region -split "," | ForEach-Object { [double]$_ }
    if (-not $parts[$a.UiMapID]) { $parts[$a.UiMapID] = @() }
    $parts[$a.UiMapID] += [ordered]@{
        mapID = [int]$a.MapID
        uiMin = [ordered]@{ x = [math]::Round($lo[0], 5); y = [math]::Round($lo[1], 5) }
        uiMax = [ordered]@{ x = [math]::Round($hi[0], 5); y = [math]::Round($hi[1], 5) }
        world = [ordered]@{ minX = [math]::Round($r[0], 2); minY = [math]::Round($r[1], 2);
                            maxX = [math]::Round($r[3], 2); maxY = [math]::Round($r[4], 2) }
    }
}

# Zone images by area ID, from wow.export's file names.
$images = @{}
Get-ChildItem -Path (Join-Path $ExportDir "zones") -Filter "Zone_*.png" | ForEach-Object {
    if ($_.Name -match '^Zone_(\d+)_') { $images[$Matches[1]] = $_.FullName }
}

$webDir = Join-Path $ExportDir "web\zones"
New-Item -ItemType Directory -Force $webDir | Out-Null
$jpeg = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq "image/jpeg" }
$params = New-Object System.Drawing.Imaging.EncoderParameters 1
$params.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality, [long]$JpegQuality)

$T = 51200 / 3 / 32           # yards per minimap tile
$TILE = 512                     # pixels per exported minimap tile
$CONTINENTS = @{ 1415 = "azeroth"; 1414 = "kalimdor" }   # UiMap ID -> wow.export map folder
$OCEAN = [System.Drawing.Color]::FromArgb(255, 4, 54, 72)   # the game's own deep-water color
# Open sea in the minimap tiles is near-black teal (mostly rgb 8,16,16, with a
# few other dark shades); repaint it as $OCEAN so it matches the game's drawn
# water and the gaps between tiles. Dark terrain keeps some red, brown or
# olive (blue below green), so it's left alone.
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
public static class MinimapSea {
    public static void Repaint(Bitmap bmp, byte r, byte g, byte b) {
        var data = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height), ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
        int length = Math.Abs(data.Stride) * bmp.Height;
        var px = new byte[length];
        Marshal.Copy(data.Scan0, px, 0, length);
        for (int i = 0; i < length; i += 4) {
            byte B = px[i], G = px[i + 1], R = px[i + 2];
            if (R <= 16 && G <= 30 && B <= 32 && G >= R && B >= G - 2 && B - G <= 8) {
                px[i] = b; px[i + 1] = g; px[i + 2] = r; px[i + 3] = 255;
            }
        }
        Marshal.Copy(px, 0, data.Scan0, length);
        bmp.UnlockBits(data);
    }
}
"@
# Mirrored edges stop the scaler from blending tile borders with nothing.
$tileAttributes = New-Object System.Drawing.Imaging.ImageAttributes
$tileAttributes.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)

function Get-Tiles([string]$dir) {
    $tiles = @{}
    $folder = Join-Path $ExportDir "maps\$dir\minimap"
    if (Test-Path $folder) {
        Get-ChildItem -Path $folder -Filter "map*.png" | ForEach-Object {
            if ($_.Name -match '^map(\d+)_(\d+)\.png$') { $tiles["$([int]$Matches[1]),$([int]$Matches[2])"] = $_.FullName }
        }
    }
    return $tiles
}

function Save-Jpeg($bitmap, [string]$path) {
    New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
    $bitmap.Save($path, $jpeg, $params)
}

# Draw the minimap tiles covering tile rectangle [left, right) x [top, bottom)
# into a width x height image. Gaps are ocean.
function Draw-Terrain($tiles, [double]$left, [double]$top, [double]$right, [double]$bottom, [int]$width, [int]$height) {
    $bmp = New-Object System.Drawing.Bitmap $width, $height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear($OCEAN)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $sx = $width / ($right - $left); $sy = $height / ($bottom - $top)
    for ($ty = [math]::Floor($top); $ty -lt [math]::Ceiling($bottom); $ty++) {
        for ($tx = [math]::Floor($left); $tx -lt [math]::Ceiling($right); $tx++) {
            $file = $tiles["$tx,$ty"]
            if (-not $file) { continue }
            $img = New-Object System.Drawing.Bitmap $file
            try {
                [MinimapSea]::Repaint($img, $OCEAN.R, $OCEAN.G, $OCEAN.B)
                # Half a pixel extra each way hides seams between scaled tiles.
                $x0 = (($tx - $left) * $sx) - 0.5; $y0 = (($ty - $top) * $sy) - 0.5
                $corners = [System.Drawing.PointF[]]@(
                    (New-Object System.Drawing.PointF $x0, $y0),
                    (New-Object System.Drawing.PointF ($x0 + $sx + 1), $y0),
                    (New-Object System.Drawing.PointF $x0, ($y0 + $sy + 1)))
                $source = New-Object System.Drawing.RectangleF 0, 0, $img.Width, $img.Height
                $g.DrawImage($img, $corners, $source, [System.Drawing.GraphicsUnit]::Pixel, $tileAttributes)
            } finally { $img.Dispose() }
        }
    }
    $g.Dispose()
    return $bmp
}

$maps = @()
$written = 0
$tilesByContinent = @{}
foreach ($id in $CONTINENTS.Keys) { $tilesByContinent[$id] = Get-Tiles $CONTINENTS[$id] }
$mapIDOf = @{}   # continent instance (0 or 1) -> continent UiMap ID
foreach ($id in $CONTINENTS.Keys) { if ($whole["$id"]) { $mapIDOf[[int]$whole["$id"].MapID] = $id } }

# Each continent's overview covers its zones plus one tile of sea, so stray
# far-off tiles (lone islands, test areas) don't stretch it.
$bounds = @{}
foreach ($m in $uiMaps) {
    $a = $whole[$m.ID]
    $continent = if ($a) { $mapIDOf[[int]$a.MapID] } else { $null }
    if (-not $a -or [int]$m.Type -ne 3 -or [int]$m.ParentUiMapID -ne $continent) { continue }
    $r = $a.Region -split "," | ForEach-Object { [double]$_ }
    $box = @((32 - $r[4] / $T), (32 - $r[3] / $T), (32 - $r[1] / $T), (32 - $r[0] / $T))   # left, top, right, bottom
    $b = $bounds[$continent]
    if (-not $b) { $bounds[$continent] = $box; continue }
    $bounds[$continent] = @([math]::Min($b[0], $box[0]), [math]::Min($b[1], $box[1]), [math]::Max($b[2], $box[2]), [math]::Max($b[3], $box[3]))
}

foreach ($m in $uiMaps) {
    $a = $whole[$m.ID]
    # A map needs a world rectangle, or parts (the Azeroth world map has only parts).
    if (-not $a -and -not $parts[$m.ID]) { continue }
    $entry = [ordered]@{
        uiMapID   = [int]$m.ID
        name      = $m.Name_lang
        parent    = [int]$m.ParentUiMapID
        type      = [int]$m.Type        # 1 world, 2 continent, 3 zone or city, 6 battleground
        mapID     = $null               # the continent or instance the map sits on
        areaID    = 0
        world     = $null
        image     = $null
        terrain   = $null
    }
    if ($a) {
        $r = $a.Region -split "," | ForEach-Object { [double]$_ }
        $entry.mapID = [int]$a.MapID
        $entry.areaID = [int]$a.AreaID
        $entry.world = [ordered]@{ minX = [math]::Round($r[0], 2); minY = [math]::Round($r[1], 2);
                                   maxX = [math]::Round($r[3], 2); maxY = [math]::Round($r[4], 2) }
    }
    $id = [int]$m.ID
    if ($parts[$m.ID]) { $entry.parts = @($parts[$m.ID] | ForEach-Object { New-Object PSObject -Property $_ }) }
    $png = if ($a) { $images[$a.AreaID] } else { $null }
    if ($png) {
        $img = [System.Drawing.Image]::FromFile($png)
        try { $img.Save((Join-Path $webDir "$id.jpg"), $jpeg, $params) } finally { $img.Dispose() }
        $entry.image = "zones/$id.jpg"
        $written++
    }

    # Continents: stitch the minimap tiles around their zones into one overview.
    if ($CONTINENTS.ContainsKey($id) -and $tilesByContinent[$id].Count -gt 0 -and $bounds[$id]) {
        $b = $bounds[$id]
        $minTX = [int][math]::Floor($b[0]) - 1; $maxTX = [int][math]::Ceiling($b[2])
        $minTY = [int][math]::Floor($b[1]) - 1; $maxTY = [int][math]::Ceiling($b[3])
        $w = ($maxTX - $minTX + 1) * $OverviewTilePixels; $h = ($maxTY - $minTY + 1) * $OverviewTilePixels
        $bmp = Draw-Terrain $tilesByContinent[$id] $minTX $minTY ($maxTX + 1) ($maxTY + 1) $w $h
        try { Save-Jpeg $bmp (Join-Path $ExportDir "web\continents\$id.jpg") } finally { $bmp.Dispose() }
        $entry.minimap = [ordered]@{ dir = $CONTINENTS[$id]; tileYards = [math]::Round($T, 4)
            tiles = [ordered]@{ minX = $minTX; maxX = $maxTX; minY = $minTY; maxY = $maxTY }
            pixelsPerTile = $OverviewTilePixels; image = "continents/$id.jpg" }
        Write-Host ("{0}: overview {1}x{2} from {3} tiles" -f $m.Name_lang, $w, $h, $tilesByContinent[$id].Count)
    }

    # Zones and cities on a continent: cut their rectangle from the terrain.
    $continent = if ($a) { $mapIDOf[[int]$a.MapID] } else { $null }
    if ([int]$m.Type -eq 3 -and $continent -and $tilesByContinent[$continent].Count -gt 0) {
        $left = 32 - $r[4] / $T; $right = 32 - $r[1] / $T     # world Y (west) -> tile column
        $top = 32 - $r[3] / $T; $bottom = 32 - $r[0] / $T     # world X (north) -> tile row
        $bmp = Draw-Terrain $tilesByContinent[$continent] $left $top $right $bottom 1002 668
        try { Save-Jpeg $bmp (Join-Path $ExportDir "web\terrain\$id.jpg") } finally { $bmp.Dispose() }
        $entry.terrain = "terrain/$id.jpg"
    }
    $maps += New-Object PSObject -Property $entry
}

$json = $maps | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText((Join-Path $PSScriptRoot "maps.json"), $json, (New-Object System.Text.UTF8Encoding $false))
$terrain = ($maps | Where-Object { $_.terrain }).Count
Write-Host ("{0} maps in maps.json; {1} parchment zone maps, {2} terrain zone maps" -f $maps.Count, $written, $terrain)
