param(
    [string]$ExportDir = (Join-Path $PSScriptRoot "export"),
    [int]$JpegQuality = 85,   # zone maps
    [int]$TileQuality = 80,   # web map tiles
    [int]$MinTileZoom = 3     # the most zoomed-out web map tiles
)
# Turns wow.export output into what the website uses:
#   art\export\web\tiles\<z>\<x>\<y>.jpg    the web map: Kalimdor and the Eastern
#                                           Kingdoms cut from the minimap terrain
#   art\export\web\zones\<UiMapID>.jpg      each zone's parchment map, named by the
#                                           game's map ID (the ID the addon records)
#   art\export\web\terrain\<UiMapID>.jpg    the same zone cut from the minimap terrain
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
#
# The web map measures everything in minimap tiles: x runs east, y south,
# and each continent sits where the game's Azeroth map (947) draws it, moved
# to the nearest whole tile (maps.json has it as minimap.layout). A web tile
# is 256px and covers 2^(8-z) minimap tiles a side, so at zoom 8 it's exactly
# one minimap tile at half size and at zoom 9 a quarter of one at full size.
# In Leaflet with CRS.Simple, [lat, lng] = [-y, x] and the tiles load from
# tiles/{z}/{x}/{y}.jpg (zoom 3 to 9; open sea has no tiles).
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = "Stop"
$started = Get-Date

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
function Quality([int]$quality) {
    $p = New-Object System.Drawing.Imaging.EncoderParameters 1
    $p.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality, [long]$quality)
    return $p
}
$params = Quality $JpegQuality
$tileParams = Quality $TileQuality

$T = 51200 / 3 / 32           # yards per minimap tile
$TILE = 512                     # pixels per exported minimap tile
$CONTINENTS = @{ 1415 = "azeroth"; 1414 = "kalimdor" }   # UiMap ID -> wow.export map folder
# Sea color for the whole web map: the minimap's most common open water,
# averaged over tiles that are all sea. The website's --sea matches it.
$OCEAN = [System.Drawing.Color]::FromArgb(255, 27, 49, 68)
# The minimap draws open water in a few flat shades that change at tile
# edges (mostly rgb 27,51,71, some 4,54,72 and 32,66,98), and the void past
# the map's edge as near-black teal (mostly 8,16,16). Left alone, every
# change shows as a box at a distance, so all of it becomes $OCEAN. Water is
# dark, blue over green over red; dark terrain keeps more red, brown or olive
# (blue below green), and snow and lit shallows are too bright, so they're
# left alone. A few tiles out at sea are void with a strip of flat,
# untextured ground along an edge (unfinished terrain north of Azshara);
# those become sea entirely.
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
public static class MinimapSea {
    static bool IsVoid(int R, int G, int B) {
        return R <= 16 && G <= 30 && B <= 32 && G >= R && B >= G - 2 && B - G <= 8;
    }
    static bool IsSea(int R, int G, int B) {
        return IsVoid(R, G, B) || (R <= 45 && G * 2 >= R * 3 + 10 && B >= G + 8 && B <= 125 && B - R >= 30);
    }
    // Mostly void, and the rest mostly a single flat color: not real ground.
    static bool IsPlaceholder(byte[] px) {
        int total = px.Length / 4, voids = 0, other = 0, best = 0;
        var colors = new Dictionary<int, int>();
        for (int i = 0; i < px.Length; i += 4) {
            int B = px[i], G = px[i + 1], R = px[i + 2];
            if (IsVoid(R, G, B)) { voids++; continue; }
            if (IsSea(R, G, B)) continue;
            other++;
            int key = (R << 16) | (G << 8) | B, n;
            colors.TryGetValue(key, out n);
            colors[key] = ++n;
            if (n > best) best = n;
        }
        return voids >= total * 0.85 && other > 0 && best * 2 >= other;
    }
    public static void Repaint(Bitmap bmp, byte r, byte g, byte b) {
        var data = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height), ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
        int length = Math.Abs(data.Stride) * bmp.Height;
        var px = new byte[length];
        Marshal.Copy(data.Scan0, px, 0, length);
        bool placeholder = IsPlaceholder(px);
        for (int i = 0; i < length; i += 4) {
            if (placeholder || IsSea(px[i + 2], px[i + 1], px[i])) {
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

function New-Canvas([int]$width, [int]$height) {
    $bmp = New-Object System.Drawing.Bitmap $width, $height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear($OCEAN)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    return $bmp, $g
}

# A minimap tile with its sea repainted. Neighboring zones share tiles, so
# recent ones are kept; the oldest go past 96.
$tileCache = @{}
$tileOrder = New-Object 'System.Collections.Generic.Queue[string]'
function Get-TileImage([string]$file) {
    $img = $tileCache[$file]
    if ($img) { return $img }
    $img = New-Object System.Drawing.Bitmap $file
    [MinimapSea]::Repaint($img, $OCEAN.R, $OCEAN.G, $OCEAN.B)
    $tileCache[$file] = $img
    $tileOrder.Enqueue($file)
    if ($tileOrder.Count -gt 96) {
        $old = $tileOrder.Dequeue()
        $tileCache[$old].Dispose()
        $tileCache.Remove($old)
    }
    return $img
}

# Draw the minimap tiles covering tile rectangle [left, right) x [top, bottom)
# into a width x height image. Gaps are ocean.
function Draw-Terrain($tiles, [double]$left, [double]$top, [double]$right, [double]$bottom, [int]$width, [int]$height) {
    $bmp, $g = New-Canvas $width $height
    $sx = $width / ($right - $left); $sy = $height / ($bottom - $top)
    for ($ty = [math]::Floor($top); $ty -lt [math]::Ceiling($bottom); $ty++) {
        for ($tx = [math]::Floor($left); $tx -lt [math]::Ceiling($right); $tx++) {
            $file = $tiles["$tx,$ty"]
            if (-not $file) { continue }
            $img = Get-TileImage $file
            # Half a pixel extra each way hides seams between scaled tiles.
            $x0 = (($tx - $left) * $sx) - 0.5; $y0 = (($ty - $top) * $sy) - 0.5
            $corners = [System.Drawing.PointF[]]@(
                (New-Object System.Drawing.PointF $x0, $y0),
                (New-Object System.Drawing.PointF ($x0 + $sx + 1), $y0),
                (New-Object System.Drawing.PointF $x0, ($y0 + $sy + 1)))
            $source = New-Object System.Drawing.RectangleF 0, 0, $img.Width, $img.Height
            $g.DrawImage($img, $corners, $source, [System.Drawing.GraphicsUnit]::Pixel, $tileAttributes)
        }
    }
    $g.Dispose()
    return $bmp
}

# A square copy of a bitmap at another size.
function Resize-Square($bitmap, [int]$size) {
    $out = New-Object System.Drawing.Bitmap $size, $size
    $g = [System.Drawing.Graphics]::FromImage($out)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.DrawImage($bitmap, (New-Object System.Drawing.Rectangle 0, 0, $size, $size), 0, 0, $bitmap.Width, $bitmap.Height,
                 [System.Drawing.GraphicsUnit]::Pixel, $tileAttributes)
    $g.Dispose()
    return $out
}

$maps = @()
$written = 0
$tilesByContinent = @{}
foreach ($id in $CONTINENTS.Keys) { $tilesByContinent[$id] = Get-Tiles $CONTINENTS[$id] }
$mapIDOf = @{}   # continent instance (0 or 1) -> continent UiMap ID
foreach ($id in $CONTINENTS.Keys) { if ($whole["$id"]) { $mapIDOf[[int]$whole["$id"].MapID] = $id } }

# Each continent's web map covers its zones plus one tile of sea, so stray
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
$crop = @{}
foreach ($id in $bounds.Keys) {
    $b = $bounds[$id]
    $crop[$id] = [ordered]@{ minX = [int][math]::Floor($b[0]) - 1; maxX = [int][math]::Ceiling($b[2]);
                             minY = [int][math]::Floor($b[1]) - 1; maxY = [int][math]::Ceiling($b[3]) }
}

# Where each continent sits on the web map: where the Azeroth map draws it
# (its 1500 x 1000 units turned into minimap tiles), rounded to whole tiles
# so every minimap tile lands exactly on the web tile grid.
$fit = @{}
foreach ($p in $parts["947"]) {
    $id = $mapIDOf[[int]$p.mapID]
    if (-not $id) { continue }
    $R = $p.world; $du = $p.uiMax.x - $p.uiMin.x; $dv = $p.uiMax.y - $p.uiMin.y
    $fit[$id] = @{
        perX = 1500 * $T * $du / ($R.maxY - $R.minY)   # map units per minimap tile
        perY = 1000 * $T * $dv / ($R.maxX - $R.minX)
        x0 = 1500 * ($p.uiMin.x + ($R.maxY - 32 * $T) * $du / ($R.maxY - $R.minY))   # where tile 0,0 lands
        y0 = 1000 * ($p.uiMin.y + ($R.maxX - 32 * $T) * $dv / ($R.maxX - $R.minX))
    }
}
$unit = ($fit.Values | ForEach-Object { $_.perX; $_.perY } | Measure-Object -Average).Average
$layout = @{}
foreach ($id in $fit.Keys) {
    $layout[$id] = [ordered]@{ x = [int][math]::Round($fit[$id].x0 / $unit); y = [int][math]::Round($fit[$id].y0 / $unit) }
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

    # Continents: which minimap tiles the web map uses, and where they go.
    if ($CONTINENTS.ContainsKey($id) -and $crop[$id] -and $layout[$id]) {
        $entry.minimap = [ordered]@{ dir = $CONTINENTS[$id]; tileYards = [math]::Round($T, 4)
            tiles = $crop[$id]; layout = $layout[$id] }
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

# The web map's tiles. Each minimap tile is read once: its quarters are zoom
# 9 tiles, its half-size copy a zoom 8 tile, and smaller copies go into the
# zoom 7 and wider tiles, which are saved once they're all filled in.
$tileDir = Join-Path $ExportDir "web\tiles"
if (Test-Path $tileDir) { Remove-Item -Recurse -Force $tileDir }   # tiles from an older layout
function Save-Tile($bitmap, [int]$z, [int]$x, [int]$y) {
    $dir = Join-Path $tileDir "$z\$x"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    $bitmap.Save((Join-Path $dir "$y.jpg"), $jpeg, $tileParams)
}
$wide = @{}   # "z/x/y" -> bitmap and graphics of a zoom 7-and-wider tile
$saved = 0
foreach ($id in $CONTINENTS.Keys) {
    $c = $crop[$id]; $at = $layout[$id]
    if (-not $c -or -not $at) { continue }
    foreach ($key in $tilesByContinent[$id].Keys) {
        $t = $key -split ","; $tx = [int]$t[0]; $ty = [int]$t[1]
        if ($tx -lt $c.minX -or $tx -gt $c.maxX -or $ty -lt $c.minY -or $ty -gt $c.maxY) { continue }
        $x = $tx + $at.x; $y = $ty + $at.y
        $img = New-Object System.Drawing.Bitmap $tilesByContinent[$id][$key]
        if ($img.Width -ne $TILE -or $img.Height -ne $TILE) { $sized = Resize-Square $img $TILE; $img.Dispose(); $img = $sized }
        [MinimapSea]::Repaint($img, $OCEAN.R, $OCEAN.G, $OCEAN.B)
        foreach ($q in 0..3) {
            $qx = $q % 2; $qy = [int][math]::Floor($q / 2)
            $quarter = $img.Clone((New-Object System.Drawing.Rectangle ($qx * 256), ($qy * 256), 256, 256), $img.PixelFormat)
            Save-Tile $quarter 9 (2 * $x + $qx) (2 * $y + $qy)
            $quarter.Dispose()
        }
        $level = Resize-Square $img 256
        $img.Dispose()
        Save-Tile $level 8 $x $y
        $saved += 5
        for ($z = 7; $z -ge $MinTileZoom; $z--) {
            $span = 1 -shl (8 - $z); $size = 256 / $span
            $smaller = Resize-Square $level $size
            $level.Dispose(); $level = $smaller
            $wx = [int][math]::Floor($x / $span); $wy = [int][math]::Floor($y / $span)
            $wkey = "$z/$wx/$wy"
            if (-not $wide[$wkey]) {
                $wide[$wkey] = New-Canvas 256 256
                $wide[$wkey][1].InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
                $wide[$wkey][1].PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
            }
            $spot = New-Object System.Drawing.Rectangle (($x - $wx * $span) * $size), (($y - $wy * $span) * $size), $size, $size
            $wide[$wkey][1].DrawImage($level, $spot, 0, 0, $size, $size, [System.Drawing.GraphicsUnit]::Pixel)
        }
        $level.Dispose()
    }
}
foreach ($wkey in $wide.Keys) {
    $p = $wkey -split "/"
    $wide[$wkey][1].Dispose()
    Save-Tile $wide[$wkey][0] $p[0] $p[1] $p[2]
    $wide[$wkey][0].Dispose()
    $saved++
}
foreach ($id in $layout.Keys) {
    Write-Host ("{0}: minimap tile 0,0 at web map {1},{2}" -f $CONTINENTS[$id], $layout[$id].x, $layout[$id].y)
}
Write-Host ("{0:N0} web map tiles, zoom {1} to 9, in {2:N0}s" -f $saved, $MinTileZoom, ((Get-Date) - $started).TotalSeconds)
