param(
    # Make a preview deployment (its own URL) instead of updating the live site.
    [switch]$Preview
)
# Puts the website draft online with Vercel (project "journeytracker"): builds
# it (build.ps1 -Site), stages it and the upload function (api\upload.js) as
# Vercel's prebuilt output and uploads it with the Vercel CLI. The map art is Blizzard's and stays out of git, so
# Vercel gets the built site from this machine, and vercel.json at the repo
# root stops deploys on git push (they would replace the site with the bare
# repo, which has no page).
#
#   powershell -ExecutionPolicy Bypass -File site\deploy.ps1 [-Preview]
#
# Needs Node.js and a logged-in Vercel CLI (npx vercel login). The first run
# links dist\vercel to the project.
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$dist = Join-Path $root "dist"

& (Join-Path $PSScriptRoot "build.ps1") -Site

# Vercel's Build Output API: the files as they are, plus how to serve them.
$stage = Join-Path $dist "vercel"
$output = Join-Path $stage ".vercel\output"
robocopy (Join-Path $dist "site") (Join-Path $output "static") /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "Staging the site in $output failed (robocopy exit $LASTEXITCODE)." }
# The upload function (/api/upload) with its copy of the importer's decoder.
# It reads SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY from the project's
# environment variables on Vercel.
$func = Join-Path $output "functions\api\upload.func"
if (Test-Path $func) { Remove-Item -Recurse -Force $func }
New-Item -ItemType Directory -Force $func | Out-Null
Copy-Item (Join-Path $PSScriptRoot "api\upload.js") (Join-Path $func "index.js")
Copy-Item (Join-Path $root "tools\import\decode.js") (Join-Path $func "decode.js")
[System.IO.File]::WriteAllText((Join-Path $func ".vc-config.json"),
    '{ "runtime": "nodejs22.x", "handler": "index.js", "launcherType": "Nodejs", "shouldAddHelpers": true }',
    (New-Object System.Text.UTF8Encoding $false))
# Tiles only change when the maps are rebuilt, so browsers may keep them a day.
$config = [ordered]@{
    version = 3
    routes = @(
        [ordered]@{ src = "^/tiles/(.*)$"; headers = @{ "Cache-Control" = "public, max-age=86400" }; continue = $true },
        @{ handle = "filesystem" }
    )
}
[System.IO.File]::WriteAllText((Join-Path $output "config.json"), ($config | ConvertTo-Json -Depth 5),
    (New-Object System.Text.UTF8Encoding $false))

if (-not (Test-Path (Join-Path $stage ".vercel\project.json"))) {
    npx --yes vercel@latest link --yes --project journeytracker --cwd $stage
    if ($LASTEXITCODE) { throw "Linking $stage to the Vercel project failed. Logged in? (npx vercel login)" }
}
# One archive instead of a request per file: thousands of tiles one by one
# run into Vercel's upload limits.
$deploy = @("--yes", "vercel@latest", "deploy", "--prebuilt", "--archive=tgz", "--yes", "--cwd", $stage)
if (-not $Preview) { $deploy += "--prod" }
npx @deploy
if ($LASTEXITCODE) { throw "The Vercel deploy failed." }
