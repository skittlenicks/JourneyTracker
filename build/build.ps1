<#
Builds dist\JourneyTracker-<version>.zip to share with friends.

The zip holds a single JourneyTracker\ folder with only what the game needs:
the TOC, Lua files, textures, Libs\ (code and license files) and README.txt.
Spec .md files, dev scripts, tools, .git and node_modules are never included.
The version in the file name comes from the TOC's "## Version:" line.

Usage (from the project folder):
    powershell -ExecutionPolicy Bypass -File build\build.ps1
    powershell -ExecutionPolicy Bypass -File build\build.ps1 -AddonDir "E:\...\Interface\AddOns\JourneyTracker"
#>
param(
    # The addon folder to pack. Defaults to the project's copy.
    [string]$AddonDir = (Join-Path $PSScriptRoot "..\JourneyTracker"),
    [string]$OutDir = (Join-Path $PSScriptRoot "..\dist")
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$AddonDir = (Resolve-Path $AddonDir).Path.TrimEnd('\')
$toc = Join-Path $AddonDir "JourneyTracker.toc"
if (-not (Test-Path $toc)) { throw "No JourneyTracker.toc in $AddonDir" }
$match = Select-String -Path $toc -Pattern '^##\s*Version:\s*(\S+)' | Select-Object -First 1
if (-not $match) { throw "No '## Version:' line in $toc" }
$version = $match.Matches[0].Groups[1].Value

# What goes in: game files at the top level, code and licenses under Libs\,
# and the README for friends. Everything else stays out.
$gameExtensions = @(".toc", ".lua", ".xml", ".tga", ".blp")
$files = Get-ChildItem -Path $AddonDir -Recurse -File | Where-Object {
    $rel = $_.FullName.Substring($AddonDir.Length + 1)
    if ($rel -match '(^|\\)(\.git|node_modules)(\\|$)') { return $false }
    if ($rel -like "Libs\*") {
        return ($_.Extension -in @(".lua", ".xml", ".toc")) -or ($_.Name -like "LICENSE*")
    }
    if ($rel -eq "README.txt") { return $true }
    return ($rel -notmatch '\\') -and ($_.Extension -in $gameExtensions)
} | Sort-Object FullName

New-Item -ItemType Directory -Force $OutDir | Out-Null
$zipPath = Join-Path (Resolve-Path $OutDir).Path "JourneyTracker-$version.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath } # replace an earlier build of this version

# Built with .NET directly so entry paths use forward slashes (Windows
# PowerShell's Compress-Archive writes backslashes, which some unzip tools
# don't handle).
$zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in $files) {
        $entry = "JourneyTracker/" + $file.FullName.Substring($AddonDir.Length + 1).Replace('\', '/')
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file.FullName, $entry,
            [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
} finally {
    $zip.Dispose()
}

Write-Output "Built $zipPath"
Write-Output ("{0} files:" -f $files.Count)
$files | ForEach-Object { Write-Output ("  JourneyTracker\" + $_.FullName.Substring($AddonDir.Length + 1)) }
