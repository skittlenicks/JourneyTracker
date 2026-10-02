param(
    # Make a preview deployment (its own URL) instead of updating the live site.
    [switch]$Preview
)
# Puts the website online with Vercel (project "journeytracker"): builds it
# (build.ps1 -Site), stages it and its three functions as Vercel's prebuilt
# output and uploads it with the Vercel CLI:
#   /api/upload          saves a pasted export to Supabase (api\upload.js)
#   /j/<id>              a shared journey's recap page (api\share.js)
#   /j/<id>/card.png     its link preview image (api\card.js)
# The map art is Blizzard's and stays out of git, so Vercel gets the built
# site from this machine, and vercel.json at the repo root stops deploys on
# git push (they would replace the site with the bare repo, which has no page).
#
#   powershell -ExecutionPolicy Bypass -File site\deploy.ps1 [-Preview]
#
# Needs Node.js and a logged-in Vercel CLI (npx vercel login). The first run
# links dist\vercel to the project.
#
# The project's firewall also limits uploads to 10 an hour per IP address
# (Hobby allows one rate limit rule). The rule lives on Vercel, not in this
# script; it was set up once with the CLI:
#   npx vercel firewall rules add "Limit export uploads" --condition '{"type":"path","op":"eq","value":"/api/upload"}'
#     --condition '{"type":"method","op":"eq","value":"POST"}' --action rate_limit
#     --rate-limit-requests 10 --rate-limit-window 3600 --rate-limit-keys ip --yes
#   npx vercel firewall publish --yes
# Share pages and their images need no rule: Vercel's CDN keeps each one
# (a page for an hour, an image for a day), and their IDs are 122 random
# bits, so there's nothing to find by guessing.
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$dist = Join-Path $root "dist"
$utf8 = New-Object System.Text.UTF8Encoding $false

& (Join-Path $PSScriptRoot "build.ps1") -Site

# Vercel's Build Output API: the files as they are, plus how to serve them.
$stage = Join-Path $dist "vercel"
$output = Join-Path $stage ".vercel\output"
robocopy (Join-Path $dist "site") (Join-Path $output "static") /MIR /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "Staging the site in $output failed (robocopy exit $LASTEXITCODE)." }

# The functions, each with copies of what it shares with the rest of the
# site: the importer's decoder, the rankings and the journey model, and
# ranks.js, which ranks a journey against every saved one. The share page
# also gets the page it fills in; the preview image its drawing code, the
# fonts, resvg and the logo. They read SUPABASE_URL and
# SUPABASE_SERVICE_ROLE_KEY from the project's environment variables.
function Stage-Function([string]$name, [string[]]$extra) {
    $func = Join-Path $output "functions\api\$name.func"
    if (Test-Path $func) { Remove-Item -Recurse -Force $func }
    New-Item -ItemType Directory -Force $func | Out-Null
    Copy-Item (Join-Path $PSScriptRoot "api\$name.js") (Join-Path $func "index.js")
    $shared = @((Join-Path $root "tools\import\decode.js"), (Join-Path $PSScriptRoot "api\ranks.js"),
        (Join-Path $PSScriptRoot "model.js"), (Join-Path $PSScriptRoot "rankings.js"))
    foreach ($file in $shared + $extra) { Copy-Item $file $func -Recurse }
    [System.IO.File]::WriteAllText((Join-Path $func ".vc-config.json"),
        '{ "runtime": "nodejs22.x", "handler": "index.js", "launcherType": "Nodejs", "shouldAddHelpers": true }', $utf8)
    return $func
}
Stage-Function "upload" @() | Out-Null
Stage-Function "share" @((Join-Path $dist "site\index.html")) | Out-Null
$card = Stage-Function "card" @((Join-Path $PSScriptRoot "api\preview.js"), (Join-Path $PSScriptRoot "fonts"),
    (Join-Path $PSScriptRoot "node_modules"))
Copy-Item (Join-Path $dist "site\favicon.png") (Join-Path $card "logo.png")

# The map art only changes when it's read from the game again, so browsers
# may keep it a day. /j/<id> is a shared journey's page, made by the share
# function, and /j/<id>/card.png its preview image, made by the card function.
$config = [ordered]@{
    version = 3
    routes = @(
        [ordered]@{ src = "^/(worldmap|zones)/(.*)$"; headers = @{ "Cache-Control" = "public, max-age=86400" }; continue = $true },
        [ordered]@{ src = "^/j/([^/]*)/card\.png$"; dest = "/api/card?id=`$1" },
        [ordered]@{ src = "^/j/([^/]*)/?$"; dest = "/api/share?id=`$1" },
        @{ handle = "filesystem" }
    )
}
[System.IO.File]::WriteAllText((Join-Path $output "config.json"), ($config | ConvertTo-Json -Depth 5), $utf8)

if (-not (Test-Path (Join-Path $stage ".vercel\project.json"))) {
    npx --yes vercel@latest link --yes --project journeytracker --cwd $stage
    if ($LASTEXITCODE) { throw "Linking $stage to the Vercel project failed. Logged in? (npx vercel login)" }
}
# One archive instead of a request per file, which once ran into Vercel's
# upload limits (with thousands of map tiles). The upload now and then
# drops partway ("fetch failed"), so it gets three tries.
$deploy = @("--yes", "vercel@latest", "deploy", "--prebuilt", "--archive=tgz", "--yes", "--cwd", $stage)
if (-not $Preview) { $deploy += "--prod" }
for ($try = 1; $try -le 3; $try++) {
    npx @deploy
    if (-not $LASTEXITCODE) { break }
    if ($try -eq 3) { throw "The Vercel deploy failed three times." }
    Write-Host "The deploy failed; trying again ($($try + 1) of 3)."
}
