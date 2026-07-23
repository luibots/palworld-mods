<#
  New-GuildBundle.ps1 - build a self-contained mod bundle for Discord distribution.

  Produces a single zip containing the Mod Manager + manifest + all mod paks. A guild
  member downloads it from Discord, unzips, and runs "Install Mods.bat" - the manager
  detects the local mods.json and installs from the bundled paks, no GitHub needed.
  This keeps the whole repo private while still being self-service for the guild.

      .\New-GuildBundle.ps1                    # -> GuildMods.zip next to the script
      .\New-GuildBundle.ps1 -OutPath C:\x.zip
#>
[CmdletBinding()]
param([string]$OutPath)

$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot
if (-not $OutPath) { $OutPath = Join-Path $repo 'GuildMods.zip' }

$manifestPath = Join-Path $repo 'mods.json'
if (-not (Test-Path $manifestPath)) { throw "mods.json not found in $repo" }
$manifest = (Get-Content $manifestPath -Raw -Encoding UTF8) | ConvertFrom-Json

# Stage everything a guild member needs, mirroring repo-relative paths so the
# manifest's "file" fields resolve locally.
$stage = Join-Path $env:TEMP ("guildbundle-" + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Force $stage | Out-Null
try {
  Copy-Item (Join-Path $repo 'PalworldModManager.ps1') $stage -Force
  Copy-Item $manifestPath (Join-Path $stage 'mods.json') -Force

  $missing = @()
  foreach ($mod in $manifest.mods) {
    $rel = $mod.file -replace '/', '\'
    $src = Join-Path $repo $rel
    if (-not (Test-Path $src)) { $missing += $mod.file; continue }
    $dst = Join-Path $stage $rel
    New-Item -ItemType Directory -Force (Split-Path $dst -Parent) | Out-Null
    Copy-Item $src $dst -Force
  }
  if ($missing.Count) { throw ("Missing pak file(s): " + ($missing -join ', ')) }

  # A dead-simple double-click launcher for non-technical members.
  $bat = @"
@echo off
title Palworld Guild Mods
echo   Starting the Palworld Mod Manager...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0PalworldModManager.ps1"
"@
  # write ASCII, CRLF
  [System.IO.File]::WriteAllText((Join-Path $stage 'Install Mods.bat'), ($bat -replace "`r?`n","`r`n"), (New-Object System.Text.ASCIIEncoding))

  $readme = @"
PALWORLD GUILD MODS - by Luibot & AyeGuild

1. Unzip this whole folder somewhere (Desktop is fine).
2. Double-click "Install Mods.bat".
3. Tick the mods you want, press Apply Changes. Done.

Close Palworld first. Steam version only (Game Pass can't load mods).
Server-side mods only take effect once the server is running them too.
"@
  [System.IO.File]::WriteAllText((Join-Path $stage 'READ ME FIRST.txt'), ($readme -replace "`r?`n","`r`n"), (New-Object System.Text.ASCIIEncoding))

  if (Test-Path $OutPath) { Remove-Item $OutPath -Force }
  Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $OutPath -Force

  $mb = [math]::Round((Get-Item $OutPath).Length / 1MB, 2)
  Write-Host "Built bundle: $OutPath ($mb MB, $($manifest.mods.Count) mod(s))"
  $OutPath
} finally {
  Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
}
