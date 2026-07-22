@echo off
title Palworld Mod Manager
echo.
echo   Starting the Palworld Mod Manager...
echo   (getting the latest version from the guild mod list)
echo.

set "PS1=%TEMP%\PalworldModManager.ps1"
set "URL=https://raw.githubusercontent.com/luibots/palworld-mods/master/PalworldModManager.ps1"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "try { [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12 } catch {}; try { Invoke-WebRequest -Uri '%URL%' -OutFile '%PS1%' -UseBasicParsing -TimeoutSec 30 } catch { Write-Host 'Could not download the manager. Check your internet connection.' -ForegroundColor Red; exit 1 }"

if not exist "%PS1%" (
  echo.
  echo   Could not download the Mod Manager.
  echo   Check your internet connection and try again.
  echo.
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
