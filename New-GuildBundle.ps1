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
  $brandingSource = Join-Path $repo 'branding'
  if (Test-Path -LiteralPath $brandingSource) {
    Copy-Item $brandingSource (Join-Path $stage 'branding') -Recurse -Force
  }

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

  $readme = @'
# AyeGuild Palworld Mods

```text
     _                ____       _ _     _
    / \   _   _  ___ / ___|_   _(_) | __| |
   / _ \ | | | |/ _ \ |  _| | | | | |/ _` |
  / ___ \| |_| |  __/ |_| | |_| | | | (_| |
 /_/   \_\\__, |\___|\____|\__,_|_|_|\__,_|
          |___/

          PALWORLD MOD COMMAND CENTER
              Luibot x AyeGuild
```

Welcome to the guild mod pack. You do not need to edit files, use PowerShell,
or understand how Palworld mods work. The manager handles it.

## Install In 60 Seconds

1. **Extract this entire ZIP** to a normal folder. Your Desktop is fine.
2. **Close Palworld completely.**
3. Double-click **`Install Mods.bat`**.
4. Tick the mods you want.
5. Select **Apply Changes**.
6. Start Palworld and join the guild server.

Do not run the installer from inside the ZIP preview. Extract it first.

## Updating

When the guild posts a newer bundle:

1. Close Palworld.
2. Extract the new ZIP.
3. Run **`Install Mods.bat`** from the new folder.
4. Select **Apply Changes**.

The manager replaces older versions for you.

## Removing Or Disabling A Mod

1. Close Palworld.
2. Run **`Install Mods.bat`**.
3. Untick the mod.
4. Select **Apply Changes**.

The manager removes only the selected guild mod. It does not delete saves.

## What The Labels Mean

- **Client only:** Install it on your own computer. The server does not need it.
- **Server required:** The server and participating players may need matching files.
- **Recommended:** This is part of the guild's normal setup.

## Important

- This bundle supports the **Steam version of Palworld**.
- Always close Palworld before applying changes.
- Never rename, unpack, or edit a `.pak` file.
- Your character and world progress are stored separately from these mod files.
- If the game updates, wait for the guild's compatibility notice before reinstalling.

## Troubleshooting

**Windows protected your PC**

Select **More info**, then **Run anyway**. The launcher is a guild-made script,
so it is not signed by a commercial software publisher.

**Palworld was not found**

Use the manager's browse option and select your Palworld installation folder.
That folder should contain a directory named `Pal`.

**The mod appears installed but does nothing**

Restart Palworld. For a server-required mod, the server must also be running
the compatible version.

**The game will not start after an update**

Open the manager, untick the mods, and apply changes. Send the admin a screenshot
of the manager and the error. Your saves are not removed.

## Credits

Designed, tested, and maintained by **Luibot** and **AyeGuild**.

Built for the guild. Tested before deployment. Backed up before server changes.
'@
  [System.IO.File]::WriteAllText(
    (Join-Path $stage 'README.md'),
    ($readme -replace "`r?`n","`r`n"),
    (New-Object System.Text.UTF8Encoding($false))
  )

  if (Test-Path $OutPath) { Remove-Item $OutPath -Force }
  Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $OutPath -Force

  $mb = [math]::Round((Get-Item $OutPath).Length / 1MB, 2)
  Write-Host "Built bundle: $OutPath ($mb MB, $($manifest.mods.Count) mod(s))"
  $OutPath
} finally {
  Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue
}
