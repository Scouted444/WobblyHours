# Make an update for the launcher (Windows PowerShell). Run from the game folder:
#   powershell -ExecutionPolicy Bypass -File tools\make_release.ps1 -Repo yourname/wobbly-hours
# Before running: export the game in Godot (Project > Export > Windows Desktop > Export Project) to export\WobblyHours.exe
# It makes release\WobblyHours_windows.zip, release\wobbly_hours_project.zip and release\latest.json.
# Upload those three files to a NEW GitHub release of that repo (mark it "latest"). Done: every launcher
# pointing at https://github.com/<Repo>/releases/latest/download/latest.json sees the update.
param([Parameter(Mandatory = $true)][string]$Repo, [string]$Notes = "")
$ErrorActionPreference = "Stop"
$game = Split-Path -Parent $PSScriptRoot
$version = ((Get-Content (Join-Path $game "version.txt") -Raw).Trim() -split " ")[0]
$rel = Join-Path $game "release"
New-Item -ItemType Directory -Force -Path $rel | Out-Null
$export = Join-Path $game "export"
if (Test-Path (Join-Path $export "WobblyHours.exe")) {
    Copy-Item -Force (Join-Path $game "version.txt") (Join-Path $export "version.txt")   # the launcher reads it
    Compress-Archive -Path (Join-Path $export "*") -DestinationPath (Join-Path $rel "WobblyHours_windows.zip") -Force
    Write-Host "Packed the exported game."
} else {
    Write-Host "No export\WobblyHours.exe yet: only the project zip is made (export from Godot first for .exe players)."
}
$items = Get-ChildItem -Path $game -Force | Where-Object { $_.Name -notin @(".godot", "export", "release") }
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) "wobbly_release"
if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
New-Item -ItemType Directory -Force -Path (Join-Path $tmp "wobbly_hours") | Out-Null
foreach ($i in $items) { Copy-Item -Recurse -Force $i.FullName (Join-Path $tmp "wobbly_hours") }
Compress-Archive -Path (Join-Path $tmp "wobbly_hours") -DestinationPath (Join-Path $rel "wobbly_hours_project.zip") -Force
Remove-Item -Recurse -Force $tmp
$base = "https://github.com/$Repo/releases/latest/download"
$json = [ordered]@{ version = $version; notes = $Notes; windows = "$base/WobblyHours_windows.zip"; project = "$base/wobbly_hours_project.zip" }
($json | ConvertTo-Json) | Set-Content -Encoding UTF8 (Join-Path $rel "latest.json")
"$base/latest.json" | Set-Content -Encoding ASCII (Join-Path $game "update_url.txt")

# The full download for new players: launcher + its link + the game in game\
$lexe = Join-Path $game "launcher\export\WobblyLauncher.exe"
if ((Test-Path $lexe) -and (Test-Path (Join-Path $export "WobblyHours.exe"))) {
    $pkg = Join-Path ([System.IO.Path]::GetTempPath()) "Wobbly Hours"
    if (Test-Path $pkg) { Remove-Item -Recurse -Force $pkg }
    New-Item -ItemType Directory -Force -Path (Join-Path $pkg "game") | Out-Null
    Copy-Item -Force $lexe $pkg
    Copy-Item -Recurse -Force (Join-Path $export "*") (Join-Path $pkg "game")
    (@{ url = "$base/latest.json" } | ConvertTo-Json) | Set-Content -Encoding UTF8 (Join-Path $pkg "launcher.json")
    Compress-Archive -Path $pkg -DestinationPath (Join-Path $rel "WobblyHours_with_launcher.zip") -Force
    Remove-Item -Recurse -Force $pkg
    Write-Host "Made WobblyHours_with_launcher.zip: give THIS to new players (unzip, run WobblyLauncher.exe)."
} else {
    Write-Host "Tip: open the launcher\ folder as a project in Godot and export it to launcher\export\WobblyLauncher.exe, then run this again to also get WobblyHours_with_launcher.zip for new players."
}
Write-Host ""
Write-Host "Version $version ready in $rel"
Write-Host "1. On GitHub: $Repo > Releases > Draft a new release, tag v$version, upload the files in release\, Publish."
Write-Host "   (the launcher only needs latest.json and WobblyHours_windows.zip; the others are for new players / Godot users)"
Write-Host "2. update_url.txt now points at $base/latest.json (it's inside the game, so share/export AFTER this once)."
