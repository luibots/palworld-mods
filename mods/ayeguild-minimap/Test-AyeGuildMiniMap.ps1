$ErrorActionPreference = 'Stop'

$modRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $modRoot)
$scriptPath = Join-Path $modRoot 'AyeGuildMiniMap\scripts\main.lua'
$manifestPath = Join-Path $repoRoot 'mods.json'
$script = Get-Content -LiteralPath $scriptPath -Raw
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$entry = $manifest.mods | Where-Object { $_.id -eq 'ayeguild-minimap' }

function Assert-Contains([string]$needle, [string]$message) {
    if (-not $script.Contains($needle)) {
        throw $message
    }
}

Assert-Contains 'viewport:SetClipping(1)' 'The local map viewport must clip the world texture.'
Assert-Contains 'local MAP_RENDER_SIZE = VIEW_SIZE * MAP_SCALE' 'The atlas must render larger than the viewport.'
Assert-Contains 'Left = (VIEW_SIZE / 2.0) - texture_x' 'The map must center on the player X coordinate.'
Assert-Contains 'Top = (VIEW_SIZE / 2.0) - texture_y' 'The map must center on the player Y coordinate.'
Assert-Contains 'local visible = true' 'The minimap must appear automatically after joining a world.'
Assert-Contains 'LoopAsync(100' 'The movement sampler must use the lightweight 10 Hz schedule.'

if ($script.Contains('normalized_x * MAP_SIZE')) {
    throw 'Detected the retired full-world map marker calculation.'
}
if (-not $entry -or $entry.version -ne '0.5.0-beta') {
    throw 'The minimap manifest entry is missing or has the wrong version.'
}

foreach ($file in $entry.files) {
    $path = Join-Path (Join-Path $modRoot 'AyeGuildMiniMap') ([string]$file.path)
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne ([string]$file.sha256).ToLowerInvariant()) {
        throw "Manifest hash mismatch: $($file.path)"
    }
}

Write-Host '[ok] AyeGuild MiniMap package and player-centered viewport checks passed.'
