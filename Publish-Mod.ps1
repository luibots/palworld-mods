<#
  Publish-Mod.ps1 - add (or remove) a mod from the guild mod set, in one command.

  Handles the whole chore: copies the .pak in, hashes it, updates mods.json,
  commits and pushes. Everyone's Mod Manager picks it up on next launch - you never
  have to send files on Discord again.

  Examples:
    .\Publish-Mod.ps1 -PakPath "C:\built\zzz_xprate_P.pak" -Name "2x XP" `
                      -Description "Doubles XP gain." -ServerSide -Recommended

    .\Publish-Mod.ps1 -Remove xprate

    .\Publish-Mod.ps1 -List
#>
[CmdletBinding(DefaultParameterSetName = 'Add')]
param(
  [Parameter(ParameterSetName = 'Add', Mandatory)][string]$PakPath,
  [Parameter(ParameterSetName = 'Add', Mandatory)][string]$Name,
  [Parameter(ParameterSetName = 'Add', Mandatory)][string]$Description,
  [Parameter(ParameterSetName = 'Add')][string]$Id,
  [Parameter(ParameterSetName = 'Add')][string]$Notes,
  [Parameter(ParameterSetName = 'Add')][string]$Version = '1.0.0',
  [Parameter(ParameterSetName = 'Add')][string]$GameVersion = 'v1.0.1.100619',
  [Parameter(ParameterSetName = 'Add')][ValidateSet('server-rule','client-tweak','quality-of-life','content')][string]$Category = 'server-rule',
  [Parameter(ParameterSetName = 'Add')][string[]]$Tags = @(),
  [Parameter(ParameterSetName = 'Add')][switch]$ServerSide,
  [Parameter(ParameterSetName = 'Add')][switch]$Recommended,
  [Parameter(ParameterSetName = 'Remove', Mandatory)][string]$Remove,
  [Parameter(ParameterSetName = 'List')][switch]$List,
  [switch]$NoPush
)

$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot
$manifestPath = Join-Path $repo 'mods.json'
if (-not (Test-Path $manifestPath)) { throw "mods.json not found in $repo" }

$manifest = (Get-Content $manifestPath -Raw -Encoding UTF8) | ConvertFrom-Json
$mods = @($manifest.mods)

if ($List) {
  Write-Host "=== Published mods ($($mods.Count)) ==="
  foreach ($m in $mods) {
    Write-Host ("  {0,-14} {1}" -f $m.id, $m.name)
    Write-Host ("  {0,-14} {1}" -f '', $m.description)
  }
  return
}

if ($Remove) {
  $hit = $mods | Where-Object { $_.id -eq $Remove }
  if (-not $hit) { throw "No mod with id '$Remove'. Use -List to see them." }
  $mods = @($mods | Where-Object { $_.id -ne $Remove })
  $pak = Join-Path $repo ($hit.file -replace '/', '\')
  if (Test-Path $pak) { Remove-Item $pak -Force }
  Write-Host "Removed '$($hit.name)'."
} else {
  if (-not (Test-Path $PakPath)) { throw "Pak not found: $PakPath" }
  $leaf = Split-Path $PakPath -Leaf
  if ($leaf -notlike '*.pak') { throw "That does not look like a .pak file: $leaf" }
  if (-not $Id) { $Id = ($leaf -replace '^zzz_', '' -replace '_P\.pak$', '' -replace '\.pak$', '').ToLower() }

  # Folder-per-mod layout: mods/<id>/<pak>, with mods/<id>/src/ for the build recipe.
  $modDir = Join-Path $repo "mods\$Id"
  New-Item -ItemType Directory -Force (Join-Path $modDir 'src') | Out-Null
  $dest = Join-Path $modDir $leaf
  if ((Resolve-Path $PakPath).Path -ne $dest) {
    Copy-Item $PakPath $dest -Force
  }
  $sha  = (Get-FileHash $dest -Algorithm SHA256).Hash.ToLower()
  $size = (Get-Item $dest).Length

  $entry = [ordered]@{
    id          = $Id
    name        = $Name
    description = $Description
    file        = "mods/$Id/$leaf"
    size        = $size
    sha256      = $sha
    version     = $Version
    category    = $Category
    tags        = @($Tags)
    gameVersion = $GameVersion
    verified    = (Get-Date -Format 'yyyy-MM-dd')
    enabled     = $true
    serverSide  = [bool]$ServerSide
    recommended = [bool]$Recommended
    conflicts   = @()
  }
  if ($Notes) { $entry['notes'] = $Notes }
  elseif ($ServerSide) {
    $entry['notes'] = 'The server must be running this same mod for it to take effect. If nothing changes in game, ask the admin whether the server has been updated.'
  }

  $mods = @($mods | Where-Object { $_.id -ne $Id }) + [pscustomobject]$entry
  Write-Host "Publishing '$Name' (id: $Id, $([math]::Round($size/1KB,1)) KB)"
  Write-Host "  sha256: $sha"
}

$manifest.mods = $mods
$manifest.updated = (Get-Date -Format 'yyyy-MM-dd')
# Write UTF-8 WITHOUT a BOM. PowerShell 5.1's `Out-File -Encoding utf8` prepends one,
# and a leading BOM makes ConvertFrom-Json fail with "Invalid JSON primitive" for every
# client reading the manifest - i.e. it silently breaks the Mod Manager for everyone.
$json = $manifest | ConvertTo-Json -Depth 8
[System.IO.File]::WriteAllText($manifestPath, $json, (New-Object System.Text.UTF8Encoding $false))

Push-Location $repo
try {
  $ErrorActionPreference = 'Continue'
  & git add -A 2>$null | Out-Null
  $msg = if ($Remove) { "Unpublish mod: $Remove" } else { "Publish mod: $Name" }
  & git -c user.email='palcommand@local' -c user.name='PAL COMMAND' commit -q -m $msg 2>$null | Out-Null
  if ($LASTEXITCODE -eq 0 -and -not $NoPush) {
    & git push -q origin master 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
      Write-Host ''
      Write-Host 'Pushed. Your guild will see it the next time they open the Mod Manager.'
    } else {
      Write-Host 'Committed, but the push failed - run: git push origin master'
    }
  } elseif ($NoPush) {
    Write-Host 'Committed locally (-NoPush given).'
  } else {
    Write-Host 'Nothing changed.'
  }
} finally { Pop-Location }
