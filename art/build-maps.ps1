param(
    [string]$ExportDir = (Join-Path $PSScriptRoot "export"),
    [int]$JpegQuality = 85
)
# Turns wow.export output into what the website uses:
#   art\export\web\zones\<UiMapID>.jpg   each zone map, named by the game's map ID
#                                       (the ID the addon records with C_Map)
#   art\maps.json                       every map's ID, name, parent, continent and
#                                       world rectangle (from the game's own tables)
#
# Input, exported with wow.export from the Forever client (see README):
#   art\export\zones\Zone_<AreaID>_*.png    Zones tab, Show Base Map + Show Overlays
#   art\export\UiMap.csv, UiMapAssignment.csv   Data tab, exported as CSV
#
#   powershell -ExecutionPolicy Bypass -File art\build-maps.ps1
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

$maps = @()
$written = 0
foreach ($m in $uiMaps) {
    $a = $whole[$m.ID]
    if (-not $a) { continue }
    $r = $a.Region -split "," | ForEach-Object { [double]$_ }
    $entry = [ordered]@{
        uiMapID   = [int]$m.ID
        name      = $m.Name_lang
        parent    = [int]$m.ParentUiMapID
        type      = [int]$m.Type        # 1 world, 2 continent, 3 zone or city, 6 battleground
        mapID     = [int]$a.MapID       # the continent or instance the map sits on
        areaID    = [int]$a.AreaID
        world     = [ordered]@{ minX = [math]::Round($r[0], 2); minY = [math]::Round($r[1], 2);
                                maxX = [math]::Round($r[3], 2); maxY = [math]::Round($r[4], 2) }
        image     = $null
    }
    $png = $images[$a.AreaID]
    if ($png) {
        $img = [System.Drawing.Image]::FromFile($png)
        try { $img.Save((Join-Path $webDir "$($m.ID).jpg"), $jpeg, $params) } finally { $img.Dispose() }
        $entry.image = "zones/$($m.ID).jpg"
        $written++
    }
    $maps += New-Object PSObject -Property $entry
}

$json = $maps | ConvertTo-Json -Depth 4
[System.IO.File]::WriteAllText((Join-Path $PSScriptRoot "maps.json"), $json, (New-Object System.Text.UTF8Encoding $false))
Write-Host ("{0} maps in maps.json, {1} zone images written to {2}" -f $maps.Count, $written, $webDir)
