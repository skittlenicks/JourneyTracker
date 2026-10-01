param(
    [string]$OutDir = (Join-Path $PSScriptRoot "..\dist")
)
# Builds the recap website draft (sample data) into one self-contained page:
#   dist\road-to-60.html
# It fills recap.template.html with the logo, a sample export string and the
# zone maps the sample uses. The maps come from art\export\web\zones (run
# art\build-maps.ps1 first); they're Blizzard's art, so the built page goes to
# the git-ignored dist\ folder, not the repo.
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
foreach ($match in [regex]::Matches($html, "__MAP_(\d+)__")) {
    $file = Join-Path $root ("art\export\web\zones\{0}.jpg" -f $match.Groups[1].Value)
    if (-not (Test-Path $file)) { throw "Missing $file. Run art\build-maps.ps1 first." }
    $html = $html.Replace($match.Value, (DataUri "image/jpeg" ([System.IO.File]::ReadAllBytes($file))))
}

New-Item -ItemType Directory -Force $OutDir | Out-Null
$out = Join-Path (Resolve-Path $OutDir) "road-to-60.html"
[System.IO.File]::WriteAllText($out, $html, (New-Object System.Text.UTF8Encoding $false))
Write-Host ("Built {0} ({1:N0} KB)" -f $out, ((Get-Item $out).Length / 1KB))
