<#
  Proves that the packaged FOV mod changes one scalar and nothing else.
#>
[CmdletBinding()]
param(
  [string]$PakPath,
  [string]$GamePak = 'C:\Program Files (x86)\Steam\steamapps\common\Palworld\Pal\Content\Paks\Pal-Windows.pak',
  [string]$Repak = 'C:\Users\llllllllllllllllllll\projects\pal-command\tools\repak.exe'
)

$ErrorActionPreference = 'Stop'
$modRoot = Split-Path $PSScriptRoot -Parent
if (-not $PakPath) { $PakPath = Join-Path $modRoot 'zzz_ayeguild_fov150_P.pak' }
$asset = 'Pal/Content/Pal/Blueprint/System/BP_PalOptionSubsystem'
$work = Join-Path $env:TEMP ("fov150-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))

if (-not (Test-Path -LiteralPath $PakPath)) { throw "Mod pak not found: $PakPath" }
if (-not (Test-Path -LiteralPath $GamePak)) { throw "Game pak not found: $GamePak" }
if (-not (Test-Path -LiteralPath $Repak)) { throw "repak not found: $Repak" }

New-Item -ItemType Directory -Force $work | Out-Null
try {
  $vanilla = Join-Path $work 'vanilla'
  $modded = Join-Path $work 'modded'
  & $Repak unpack -q -f -o $vanilla -i "$asset.uasset" -i "$asset.uexp" $GamePak
  if ($LASTEXITCODE -ne 0) { throw 'Could not extract vanilla option asset.' }
  & $Repak unpack -q -f -o $modded $PakPath
  if ($LASTEXITCODE -ne 0) { throw 'Could not extract mod option asset.' }

  $vanAsset = Join-Path $vanilla ($asset -replace '/', '\')
  $modAsset = Join-Path $modded ($asset -replace '/', '\')
  $changed = @()

  foreach ($ext in @('.uasset', '.uexp')) {
    $a = [IO.File]::ReadAllBytes("$vanAsset$ext")
    $b = [IO.File]::ReadAllBytes("$modAsset$ext")
    if ($a.Length -ne $b.Length) { throw "$ext length changed." }
    for ($i = 0; $i -lt $a.Length; $i++) {
      if ($a[$i] -ne $b[$i]) { $changed += "$ext@$i" }
    }
  }

  $vanExp = [IO.File]::ReadAllBytes("$vanAsset.uexp")
  $modExp = [IO.File]::ReadAllBytes("$modAsset.uexp")
  $old = [BitConverter]::ToSingle($vanExp, 604)
  $new = [BitConverter]::ToSingle($modExp, 604)
  $expected = @('.uexp@606', '.uexp@607')

  if ($old -ne 90.0 -or $new -ne 150.0) {
    throw "Expected scalar 90 -> 150; found $old -> $new."
  }
  if (($changed -join ',') -ne ($expected -join ',')) {
    throw "Unexpected binary changes: $($changed -join ', ')."
  }

  Write-Host 'PASS: FOV.Max is 90 -> 150 and no other bytes changed.' -ForegroundColor Green
} finally {
  Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
