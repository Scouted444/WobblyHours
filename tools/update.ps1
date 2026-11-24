# Wobbly Hours updater (Windows PowerShell). Called by update.bat in the game folder.
param([Parameter(Mandatory = $true)][string]$Zip)
$ErrorActionPreference = "Stop"
$game = Split-Path -Parent $PSScriptRoot          # the folder with project.godot
$Zip = $Zip.Trim('"')
if (-not (Test-Path $Zip)) { Write-Host "Can't find $Zip"; exit 1 }
if (-not (Test-Path (Join-Path $game "project.godot"))) { Write-Host "This doesn't look like the game folder: $game"; exit 1 }

$old = "unknown"
if (Test-Path (Join-Path $game "version.txt")) { $old = (Get-Content (Join-Path $game "version.txt") -Raw).Trim() }

# 1. back up the current version (code, scenes, models; not Godot's cache)
$stamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$backups = Join-Path (Split-Path -Parent $game) "wobbly_hours_backups"
New-Item -ItemType Directory -Force -Path $backups | Out-Null
$backup = Join-Path $backups "backup_$stamp.zip"
Write-Host "Backing up the current version ($old) to $backup ..."
$items = Get-ChildItem -Path $game -Force | Where-Object { $_.Name -ne ".godot" }
Compress-Archive -Path $items.FullName -DestinationPath $backup -Force

# 2. unpack the new version next to it
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("wobbly_update_" + $stamp)
Expand-Archive -Path $Zip -DestinationPath $tmp -Force
$src = $tmp
$inner = Get-ChildItem -Path $tmp -Directory | Where-Object { Test-Path (Join-Path $_.FullName "project.godot") } | Select-Object -First 1
if ($inner) { $src = $inner.FullName }
if (-not (Test-Path (Join-Path $src "project.godot"))) { Write-Host "That zip doesn't contain the game (no project.godot)."; exit 1 }

# 3. copy it over the game (new and changed files; Godot's cache folder is left alone)
Write-Host "Installing ..."
robocopy $src $game /E /XD ".godot" /NFL /NDL /NJH /NJS /NP | Out-Null
Remove-Item -Recurse -Force $tmp

$new = "?"
if (Test-Path (Join-Path $game "version.txt")) { $new = (Get-Content (Join-Path $game "version.txt") -Raw).Trim() }
Write-Host ""
Write-Host "Updated: $old  ->  $new"
Write-Host "Open the project in Godot (it re-imports the new models), then play. Backup kept in $backups"
