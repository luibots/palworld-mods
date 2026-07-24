<#
  PalworldModManager.ps1 - friendly mod installer / manager for the guild.

  Needs nothing installed: uses PowerShell + WinForms that ship with Windows.
  Finds your Palworld automatically, downloads the guild's current mod set,
  and installs or removes mods with checkboxes.

  Run with -SelfTest to verify detection + install logic without opening the window.
#>
[CmdletBinding()]
param(
  [switch]$SelfTest,
  [string]$PalworldPath,
  [string]$ManifestUrl
)

$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$RepoOwner = 'luibots'
$RepoName  = 'palworld-mods'
$Branches  = @('master','main')

# ---------------------------------------------------------------- manifest

function Get-Manifest {
  $errs = @()
  # LOCAL BUNDLE MODE: if a mods.json sits next to this script (i.e. we were unzipped from a
  # Discord bundle), install from the bundled paks instead of downloading from GitHub. This is
  # what lets distribution stay fully private - no public repo needed.
  $localManifest = Join-Path $PSScriptRoot 'mods.json'
  if (Test-Path -LiteralPath $localManifest) {
    try {
      $text = (Get-Content $localManifest -Raw) -replace "^\xEF\xBB\xBF", ''
      $text = $text.TrimStart([char]0xFEFF, [char]0x200B)
      return @{ Manifest = ($text | ConvertFrom-Json); Base = $PSScriptRoot; Local = $true }
    } catch { $errs += ("local mods.json -> {0}" -f $_.Exception.Message) }
  }
  $urls = if ($ManifestUrl) { @(@{ M = $ManifestUrl; B = (Split-Path $ManifestUrl -Parent) }) }
          else { $Branches | ForEach-Object {
            @{ M = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/$_/mods.json"
               B = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/$_" } } }
  foreach ($u in $urls) {
    try {
      $r = Invoke-WebRequest -Uri $u.M -UseBasicParsing -TimeoutSec 20
      # Strip a UTF-8 BOM if one slipped into the manifest - ConvertFrom-Json chokes on it
      # with "Invalid JSON primitive", which would break the manager for every user.
      $text = ($r.Content -replace "^\xEF\xBB\xBF", '').TrimStart([char]0xFEFF, [char]0x200B)
      return @{ Manifest = ($text | ConvertFrom-Json); Base = $u.B }
    } catch { $errs += ("{0} -> {1}" -f $u.M, $_.Exception.Message) }
  }
  throw ("Could not download the mod list. Check your internet connection. Details: " + ($errs -join ' | '))
}

# ---------------------------------------------------------------- game paths

function Find-Palworld {
  if ($PalworldPath -and (Test-Path (Join-Path $PalworldPath 'Pal\Content\Paks'))) { return $PalworldPath }
  $cands = New-Object System.Collections.Generic.List[string]
  $steamRoots = @("${env:ProgramFiles(x86)}\Steam", "$env:ProgramFiles\Steam", 'C:\Steam', 'D:\Steam')
  foreach ($sr in $steamRoots) {
    $vdf = Join-Path $sr 'steamapps\libraryfolders.vdf'
    if (Test-Path $vdf) {
      $txt = Get-Content $vdf -Raw
      foreach ($m in [regex]::Matches($txt, '"path"\s+"([^"]+)"')) {
        $p = $m.Groups[1].Value -replace '\\\\', '\'
        $cands.Add((Join-Path $p 'steamapps\common\Palworld'))
      }
    }
    $cands.Add((Join-Path $sr 'steamapps\common\Palworld'))
  }
  foreach ($d in @('C','D','E','F','G')) { $cands.Add("${d}:\SteamLibrary\steamapps\common\Palworld") }
  foreach ($c in $cands) { if (Test-Path (Join-Path $c 'Pal\Content\Paks')) { return $c } }
  return $null
}

function Test-GamePassInstall {
  foreach ($root in @("$env:ProgramFiles\WindowsApps", "$env:LOCALAPPDATA\Packages")) {
    if (Test-Path $root) {
      try {
        $hit = Get-ChildItem -LiteralPath $root -Directory -Filter '*Palworld*' -ErrorAction SilentlyContinue
        if ($hit) { return $true }
      } catch {}
    }
  }
  return $false
}

function Test-PalworldRunning {
  $null -ne (Get-Process -Name 'Palworld-Win64-Shipping','Palworld' -ErrorAction SilentlyContinue)
}

# ---------------------------------------------------------------- install ops

function Get-ModsDir([string]$pal) { Join-Path $pal 'Pal\Content\Paks\~mods' }
function Get-ModFileName($mod)     { Split-Path ($mod.file -replace '/', '\') -Leaf }

function Test-ModInstalled([string]$pal, $mod) {
  Test-Path -LiteralPath (Join-Path (Get-ModsDir $pal) (Get-ModFileName $mod))
}

function Install-Mod([string]$pal, [string]$base, $mod) {
  $dir = Get-ModsDir $pal
  if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $dest = Join-Path $dir (Get-ModFileName $mod)
  $tmp  = "$dest.part"
  # Local bundle base = copy from the bundled pak; URL base = download.
  $localPak = Join-Path $base ($mod.file -replace '/', '\')
  if (Test-Path -LiteralPath $localPak) {
    Copy-Item -LiteralPath $localPak -Destination $tmp -Force
  } else {
    Invoke-WebRequest -Uri ("{0}/{1}" -f $base, $mod.file) -OutFile $tmp -UseBasicParsing -TimeoutSec 120
  }
  if ($mod.sha256) {
    $h = (Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash.ToLower()
    if ($h -ne ([string]$mod.sha256).ToLower()) {
      Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
      throw "Download verification failed for '$($mod.name)'. Nothing was installed."
    }
  }
  Move-Item -LiteralPath $tmp -Destination $dest -Force
}

function Uninstall-Mod([string]$pal, $mod) {
  $f = Join-Path (Get-ModsDir $pal) (Get-ModFileName $mod)
  if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force }
}

function Get-UE4SSRoot([string]$pal) {
  Join-Path $pal 'Mods\NativeMods\UE4SS'
}

function Get-BetaDestination([string]$pal, $beta) {
  Join-Path (Get-UE4SSRoot $pal) ("Mods\{0}" -f $beta.modFolder)
}

function Test-BetaInstalled([string]$pal, $beta) {
  if ($beta.installType -ne 'ue4ss-lua') { return $false }
  Test-Path -LiteralPath (Join-Path (Get-BetaDestination $pal $beta) 'scripts\main.lua')
}

function Install-Beta([string]$pal, $beta) {
  if ($beta.installType -ne 'ue4ss-lua') {
    throw "Unsupported beta installer type: $($beta.installType)"
  }
  $ue4ss = Get-UE4SSRoot $pal
  if (-not (Test-Path -LiteralPath $ue4ss)) {
    throw @"
UE4SS Experimental is required for this beta.
Subscribe in Steam Workshop, enable it in Palworld's Mod Manager, launch once,
close Palworld, and then run this installer again.
"@
  }

  $stage = Join-Path $env:TEMP ("ayeguild-beta-" + [guid]::NewGuid().ToString('N'))
  $destination = Get-BetaDestination $pal $beta
  try {
    New-Item -ItemType Directory -Force $stage | Out-Null
    foreach ($file in $beta.files) {
      $relative = ([string]$file.path) -replace '/', '\'
      $stagedFile = Join-Path $stage $relative
      New-Item -ItemType Directory -Force (Split-Path $stagedFile -Parent) | Out-Null
      $url = ("{0}/{1}" -f ([string]$beta.sourceBase).TrimEnd('/'), ([string]$file.path))
      Invoke-WebRequest -Uri $url -OutFile $stagedFile -UseBasicParsing -TimeoutSec 60
      if ($file.sha256) {
        $actual = (Get-FileHash -LiteralPath $stagedFile -Algorithm SHA256).Hash.ToLower()
        if ($actual -ne ([string]$file.sha256).ToLower()) {
          throw "Download verification failed for beta file '$($file.path)'."
        }
      }
    }
    if (Test-Path -LiteralPath $destination) {
      Remove-Item -LiteralPath $destination -Recurse -Force
    }
    New-Item -ItemType Directory -Force (Split-Path $destination -Parent) | Out-Null
    Copy-Item -LiteralPath $stage -Destination $destination -Recurse -Force

    $modsFile = Join-Path $ue4ss 'Mods\mods.txt'
    $lines = if (Test-Path -LiteralPath $modsFile) { @(Get-Content -LiteralPath $modsFile) } else { @() }
    $escaped = [regex]::Escape([string]$beta.modFolder)
    $lines = @($lines | Where-Object { $_ -notmatch ("^\s*{0}\s*:" -f $escaped) })
    $lines += ("{0} : 1" -f $beta.modFolder)
    [IO.File]::WriteAllLines($modsFile, $lines, [Text.UTF8Encoding]::new($false))
  } finally {
    if (Test-Path -LiteralPath $stage) {
      Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}

function Uninstall-Beta([string]$pal, $beta) {
  $ue4ss = Get-UE4SSRoot $pal
  $destination = Get-BetaDestination $pal $beta
  if (Test-Path -LiteralPath $destination) {
    Remove-Item -LiteralPath $destination -Recurse -Force
  }
  $modsFile = Join-Path $ue4ss 'Mods\mods.txt'
  if (Test-Path -LiteralPath $modsFile) {
    $escaped = [regex]::Escape([string]$beta.modFolder)
    $lines = @(Get-Content -LiteralPath $modsFile | Where-Object {
      $_ -notmatch ("^\s*{0}\s*:" -f $escaped)
    })
    [IO.File]::WriteAllLines($modsFile, $lines, [Text.UTF8Encoding]::new($false))
  }
}

# ---------------------------------------------------------------- self test

if ($SelfTest) {
  $ok = $true
  Write-Host '=== PALWORLD MOD MANAGER - SELF TEST ==='
  $pal = Find-Palworld
  if ($pal) { Write-Host "  [ok]   Palworld found: $pal" }
  else      { Write-Host '  [FAIL] Palworld not found'; $ok = $false }
  Write-Host ("  [info] Game Pass install detected: {0}" -f (Test-GamePassInstall))
  Write-Host ("  [info] Palworld running: {0}" -f (Test-PalworldRunning))

  try {
    $mf = Get-Manifest
    Write-Host ("  [ok]   Manifest loaded from {0} ({1} mod(s))" -f $mf.Base, $mf.Manifest.mods.Count)
    foreach ($m in $mf.Manifest.mods) {
      $state = if ($pal -and (Test-ModInstalled $pal $m)) { 'INSTALLED' } else { 'not installed' }
      Write-Host ("         - {0}  [{1}]" -f $m.name, $state)
    }
    if ($pal) {
      $m0 = $mf.Manifest.mods[0]
      Write-Host "  [test] install/uninstall round trip on '$($m0.name)'..."
      $wasInstalled = Test-ModInstalled $pal $m0
      Install-Mod $pal $mf.Base $m0
      if (Test-ModInstalled $pal $m0) { Write-Host '  [ok]   install worked (hash verified)' }
      else { Write-Host '  [FAIL] install did not produce the file'; $ok = $false }
      Uninstall-Mod $pal $m0
      if (-not (Test-ModInstalled $pal $m0)) { Write-Host '  [ok]   uninstall worked' }
      else { Write-Host '  [FAIL] uninstall left the file'; $ok = $false }
      if ($wasInstalled) { Install-Mod $pal $mf.Base $m0; Write-Host '  [info] restored prior installed state' }
    }
    foreach ($beta in @($mf.Manifest.beta)) {
      $state = if ($pal -and (Test-BetaInstalled $pal $beta)) { 'BRIDGE INSTALLED' } else { 'not installed' }
      Write-Host ("  [beta] {0} [{1}] - private pilot; guided setup required" -f $beta.name, $state)
    }
  } catch { Write-Host "  [FAIL] $_"; $ok = $false }

  try {
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $f = New-Object System.Windows.Forms.Form
    $f.Text = 'probe'; $f.Dispose()
    Write-Host '  [ok]   WinForms available (GUI will render)'
  } catch { Write-Host "  [FAIL] WinForms unavailable: $_"; $ok = $false }

  Write-Host ("=== RESULT: {0} ===" -f $(if ($ok) { 'PASS' } else { 'FAIL' }))
  if (-not $ok) { exit 1 }
  exit 0
}

# ---------------------------------------------------------------- GUI

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$ink    = [System.Drawing.Color]::FromArgb(18, 20, 27)
$paper  = [System.Drawing.Color]::FromArgb(245, 246, 248)
$amber  = [System.Drawing.Color]::FromArgb(214, 138, 20)
$green  = [System.Drawing.Color]::FromArgb(22, 128, 60)
$red    = [System.Drawing.Color]::FromArgb(190, 40, 40)

$form = New-Object System.Windows.Forms.Form
$form.Text = 'AyeGuild Mod Manager'
$form.Size = New-Object System.Drawing.Size(900, 720)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $paper
$form.MinimumSize = New-Object System.Drawing.Size(820, 650)

$header = New-Object System.Windows.Forms.Panel
$header.Dock = 'Top'; $header.Height = 154; $header.BackColor = $ink

$brandImage = $null
$brandPath = Join-Path $PSScriptRoot 'branding\AyeGuild.png'
if (Test-Path -LiteralPath $brandPath) {
  try {
    $brandImage = [System.Drawing.Image]::FromFile($brandPath)
    $brand = New-Object System.Windows.Forms.PictureBox
    $brand.Location = New-Object System.Drawing.Point(12, 8)
    $brand.Size = New-Object System.Drawing.Size(138, 138)
    $brand.SizeMode = 'Zoom'
    $brand.Image = $brandImage
    $header.Controls.Add($brand)
  } catch {}
}

$title = New-Object System.Windows.Forms.Label
$title.Text = 'AYEGUILD MOD MANAGER'
$title.ForeColor = $amber
$title.Font = New-Object System.Drawing.Font('Segoe UI', 19, [System.Drawing.FontStyle]::Bold)
$title.Location = New-Object System.Drawing.Point(164, 42)
$title.AutoSize = $true
$header.Controls.Add($title)

$credit = New-Object System.Windows.Forms.Label
$credit.Text = 'PALWORLD MOD COMMAND CENTER'
$credit.ForeColor = [System.Drawing.Color]::FromArgb(150, 155, 165)
$credit.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$credit.Location = New-Object System.Drawing.Point(166, 78)
$credit.AutoSize = $true
$header.Controls.Add($credit)

$authors = New-Object System.Windows.Forms.Label
$authors.Text = 'Built by Luibot x AyeGuild'
$authors.ForeColor = [System.Drawing.Color]::FromArgb(210, 214, 222)
$authors.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$authors.Location = New-Object System.Drawing.Point(166, 104)
$authors.AutoSize = $true
$header.Controls.Add($authors)
$form.Controls.Add($header)

$pathLabel = New-Object System.Windows.Forms.Label
$pathLabel.Location = New-Object System.Drawing.Point(16, 168)
$pathLabel.Size = New-Object System.Drawing.Size(720, 34)
$pathLabel.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.Controls.Add($pathLabel)

$browse = New-Object System.Windows.Forms.Button
$browse.Text = 'Find it myself...'
$browse.Location = New-Object System.Drawing.Point(752, 168)
$browse.Size = New-Object System.Drawing.Size(110, 26)
$browse.Anchor = 'Top,Right'
$form.Controls.Add($browse)

$catalogLabel = New-Object System.Windows.Forms.Label
$catalogLabel.Text = 'MOD CATALOG'
$catalogLabel.Location = New-Object System.Drawing.Point(16, 200)
$catalogLabel.AutoSize = $true
$catalogLabel.ForeColor = $ink
$catalogLabel.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($catalogLabel)

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Location = New-Object System.Drawing.Point(16, 222)
$tabs.Size = New-Object System.Drawing.Size(846, 310)
$tabs.Anchor = 'Top,Left,Right,Bottom'
$form.Controls.Add($tabs)

$approvedTab = New-Object System.Windows.Forms.TabPage
$approvedTab.Text = 'APPROVED MODS'
$approvedTab.BackColor = [System.Drawing.Color]::White
$tabs.TabPages.Add($approvedTab)

$betaTab = New-Object System.Windows.Forms.TabPage
$betaTab.Text = 'BETA - PRIVATE PILOT'
$betaTab.BackColor = [System.Drawing.Color]::White
$tabs.TabPages.Add($betaTab)

$list = New-Object System.Windows.Forms.ListView
$list.Dock = 'Fill'
$list.View = 'Details'
$list.CheckBoxes = $true
$list.FullRowSelect = $true
$list.GridLines = $false
$list.Font = New-Object System.Drawing.Font('Segoe UI', 9)
[void]$list.Columns.Add('AyeGuild Mod', 190)
[void]$list.Columns.Add('Version', 70)
[void]$list.Columns.Add('Install', 100)
[void]$list.Columns.Add('Status', 100)
[void]$list.Columns.Add('What it does', 340)
$approvedTab.Controls.Add($list)

$betaWarning = New-Object System.Windows.Forms.Label
$betaWarning.Text = 'PRIVATE PILOT: LUIS ONLY. Installing the bridge is not the full setup. UE4SS, Ollama, Python, indexed game data, and the local companion service are required.'
$betaWarning.ForeColor = $red
$betaWarning.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$betaWarning.Location = New-Object System.Drawing.Point(8, 8)
$betaWarning.Size = New-Object System.Drawing.Size(810, 38)
$betaWarning.Anchor = 'Top,Left,Right'
$betaTab.Controls.Add($betaWarning)

$betaList = New-Object System.Windows.Forms.ListView
$betaList.Location = New-Object System.Drawing.Point(8, 50)
$betaList.Size = New-Object System.Drawing.Size(812, 224)
$betaList.View = 'Details'
$betaList.CheckBoxes = $true
$betaList.FullRowSelect = $true
$betaList.GridLines = $false
$betaList.Font = New-Object System.Drawing.Font('Segoe UI', 9)
[void]$betaList.Columns.Add('Private Beta', 190)
[void]$betaList.Columns.Add('Version', 70)
[void]$betaList.Columns.Add('Installs', 120)
[void]$betaList.Columns.Add('Status', 105)
[void]$betaList.Columns.Add('Setup warning', 300)
$betaList.Anchor = 'Top,Bottom,Left,Right'
$betaTab.Controls.Add($betaList)

$apply = New-Object System.Windows.Forms.Button
$apply.Text = 'Apply Changes'
$apply.Location = New-Object System.Drawing.Point(16, 544)
$apply.Size = New-Object System.Drawing.Size(140, 34)
$apply.BackColor = $amber
$apply.ForeColor = [System.Drawing.Color]::White
$apply.FlatStyle = 'Flat'
$apply.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$apply.Anchor = 'Left,Bottom'
$form.Controls.Add($apply)

$refresh = New-Object System.Windows.Forms.Button
$refresh.Text = 'Refresh'
$refresh.Location = New-Object System.Drawing.Point(166, 544)
$refresh.Size = New-Object System.Drawing.Size(90, 34)
$refresh.Anchor = 'Left,Bottom'
$form.Controls.Add($refresh)

$openDir = New-Object System.Windows.Forms.Button
$openDir.Text = 'Open Mods Folder'
$openDir.Location = New-Object System.Drawing.Point(266, 544)
$openDir.Size = New-Object System.Drawing.Size(140, 34)
$openDir.Anchor = 'Left,Bottom'
$form.Controls.Add($openDir)

$betaGuide = New-Object System.Windows.Forms.Button
$betaGuide.Text = 'Beta Setup Guide'
$betaGuide.Location = New-Object System.Drawing.Point(416, 544)
$betaGuide.Size = New-Object System.Drawing.Size(140, 34)
$betaGuide.Anchor = 'Left,Bottom'
$form.Controls.Add($betaGuide)

$status = New-Object System.Windows.Forms.TextBox
$status.Location = New-Object System.Drawing.Point(16, 588)
$status.Size = New-Object System.Drawing.Size(846, 84)
$status.Multiline = $true
$status.ReadOnly = $true
$status.ScrollBars = 'Vertical'
$status.BackColor = [System.Drawing.Color]::White
$status.Font = New-Object System.Drawing.Font('Consolas', 9)
$status.Anchor = 'Left,Right,Bottom'
$form.Controls.Add($status)

$script:pal      = $null
$script:base     = $null
$script:mods     = @()
$script:betas    = @()

function Say([string]$m, [string]$kind = 'info') {
  $prefix = switch ($kind) { 'ok' { '[ok]   ' } 'err' { '[!]    ' } default { '       ' } }
  $status.AppendText($prefix + $m + "`r`n")
  $status.SelectionStart = $status.TextLength
  $status.ScrollToCaret()
  [System.Windows.Forms.Application]::DoEvents()
}

function Refresh-Everything {
  $list.Items.Clear()
  $betaList.Items.Clear()
  $script:pal = Find-Palworld
  if ($script:pal) {
    $pathLabel.ForeColor = $green
    $pathLabel.Text = "Palworld found:  $($script:pal)"
  } else {
    $pathLabel.ForeColor = $red
    if (Test-GamePassInstall) {
      $pathLabel.Text = 'Xbox / Game Pass version detected. Mods only work on the Steam version.'
      Say 'You appear to have Palworld from Xbox Game Pass. That version does not support these mods - only the Steam version does.' 'err'
    } else {
      $pathLabel.Text = 'Could not find Palworld automatically - click "Find it myself..."'
      Say 'Could not find your Palworld folder. Click "Find it myself..." and pick the Palworld folder.' 'err'
    }
  }

  try {
    $mf = Get-Manifest
    $script:base = $mf.Base
    $script:mods = @($mf.Manifest.mods)
    $script:betas = @($mf.Manifest.beta)
    Say ("Loaded the guild mod list ({0} mod(s))." -f $script:mods.Count) 'ok'
    if ($script:betas.Count) {
      Say ("Loaded {0} private beta pilot(s). Beta setup is intentionally separate from approved mods." -f $script:betas.Count)
    }
    Say 'PAL COMMAND companion: /players and the admin dashboard show live, copyable in-game map coordinates.'
  } catch {
    Say "$_" 'err'
    return
  }

  foreach ($m in $script:mods) {
    $installed = $script:pal -and (Test-ModInstalled $script:pal $m)
    $it = New-Object System.Windows.Forms.ListViewItem($m.name)
    [void]$it.SubItems.Add($(if ($m.version) { "v$($m.version)" } else { '-' }))
    [void]$it.SubItems.Add($(if ($m.serverSide) { 'Server + client' } else { 'Client only' }))
    [void]$it.SubItems.Add($(if ($installed) { 'Installed' } else { 'Not installed' }))
    [void]$it.SubItems.Add([string]$m.description)
    $it.Checked = [bool]$installed
    $it.Tag = $m
    if ($installed) { $it.ForeColor = $green }
    [void]$list.Items.Add($it)
  }
  foreach ($beta in $script:betas) {
    $installed = $script:pal -and (Test-BetaInstalled $script:pal $beta)
    $it = New-Object System.Windows.Forms.ListViewItem($beta.name)
    [void]$it.SubItems.Add($(if ($beta.version) { "v$($beta.version)" } else { '-' }))
    [void]$it.SubItems.Add('UE4SS bridge only')
    [void]$it.SubItems.Add($(if ($installed) { 'Bridge installed' } else { 'Not installed' }))
    [void]$it.SubItems.Add([string]$beta.warning)
    $it.Checked = [bool]$installed
    $it.Tag = $beta
    if ($installed) { $it.ForeColor = $green } else { $it.ForeColor = $red }
    [void]$betaList.Items.Add($it)
  }
  if (-not $script:pal) { return }
  $anyRec = $script:mods | Where-Object { $_.recommended -and -not (Test-ModInstalled $script:pal $_) }
  if ($anyRec) { Say 'Tip: tick the recommended mods above, then press Apply Changes.' }
}

$apply.Add_Click({
  if (-not $script:pal) { Say 'Pick your Palworld folder first.' 'err'; return }
  if (Test-PalworldRunning) {
    [System.Windows.Forms.MessageBox]::Show('Please close Palworld first, then press Apply again.', 'Palworld is running') | Out-Null
    Say 'Palworld is running - close the game and try again.' 'err'
    return
  }
  $apply.Enabled = $false
  try {
    foreach ($it in $list.Items) {
      $m = $it.Tag
      $installed = Test-ModInstalled $script:pal $m
      if ($it.Checked -and -not $installed) {
        Say "Installing $($m.name)..."
        Install-Mod $script:pal $script:base $m
        Say "$($m.name) installed." 'ok'
      } elseif (-not $it.Checked -and $installed) {
        Say "Removing $($m.name)..."
        Uninstall-Mod $script:pal $m
        Say "$($m.name) removed." 'ok'
      }
    }
    foreach ($it in $betaList.Items) {
      $beta = $it.Tag
      $installed = Test-BetaInstalled $script:pal $beta
      if ($it.Checked -and -not $installed) {
        $warning = @"
$($beta.name) is a private beta for Luis only.

This installs only the UE4SS in-game bridge. It does NOT install or configure Ollama,
Python, game-data indexing, the local API, or web/live integrations. The feature may
break after a Palworld update and can affect game performance while AI models are loaded.

Continue with the bridge installation?
"@
        $answer = [System.Windows.Forms.MessageBox]::Show(
          $warning,
          'Private beta - substantial setup required',
          [System.Windows.Forms.MessageBoxButtons]::YesNo,
          [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
          $it.Checked = $false
          Say "$($beta.name) beta installation cancelled."
          continue
        }
        Say "Installing private beta bridge: $($beta.name)..."
        Install-Beta $script:pal $beta
        Say "$($beta.name) bridge installed. Complete the setup guide before pressing F2 in game." 'ok'
      } elseif (-not $it.Checked -and $installed) {
        Say "Removing private beta bridge: $($beta.name)..."
        Uninstall-Beta $script:pal $beta
        Say "$($beta.name) bridge removed. Local companion files and Ollama were left untouched." 'ok'
      }
    }
    Say 'All done. You can start Palworld now.' 'ok'
  } catch {
    Say "$_" 'err'
  } finally {
    $apply.Enabled = $true
    $sel = @{}
    foreach ($it in $list.Items) { $sel[$it.Text] = $it.Checked }
    Refresh-Everything
  }
})

$refresh.Add_Click({ Refresh-Everything })

$openDir.Add_Click({
  if (-not $script:pal) { Say 'Pick your Palworld folder first.' 'err'; return }
  $d = Get-ModsDir $script:pal
  if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
  Start-Process explorer.exe $d
})

$betaGuide.Add_Click({
  $beta = $script:betas | Select-Object -First 1
  if (-not $beta -or -not $beta.setupUrl) {
    Say 'No beta setup guide is available.' 'err'
    return
  }
  Start-Process ([string]$beta.setupUrl)
})

$browse.Add_Click({
  $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
  $dlg.Description = 'Select your Palworld folder (the one containing the Pal folder)'
  if ($dlg.ShowDialog() -eq 'OK') {
    if (Test-Path (Join-Path $dlg.SelectedPath 'Pal\Content\Paks')) {
      # Find-Palworld reads the script-scoped $PalworldPath, so set it there.
      $script:PalworldPath = $dlg.SelectedPath
      Refresh-Everything
    } else {
      [System.Windows.Forms.MessageBox]::Show('That does not look like the Palworld folder. It should contain a folder named "Pal".', 'Wrong folder') | Out-Null
    }
  }
})

Say 'Looking for your Palworld installation...'
Refresh-Everything
[void]$form.ShowDialog()
if ($brandImage) { $brandImage.Dispose() }
