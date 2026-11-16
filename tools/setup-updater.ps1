# One-time setup for the WritPath updater (run "Setup Updater.bat" next to this file).
# - remembers where your AddOns folder is
# - puts an "Update WritPath" shortcut on your desktop
# - checks for a new WritPath each time you log in to Windows (quietly; a log is kept)
# Nothing here needs administrator rights. To undo: delete the two shortcuts and %LOCALAPPDATA%\WritPath.
$ErrorActionPreference = 'Stop'
try {
  $addonDir = Split-Path -Parent $PSScriptRoot          # ...\AddOns\WritPath
  $addOns   = Split-Path -Parent $addonDir              # ...\AddOns
  $name     = Split-Path -Leaf $addonDir
  if ($name -ne 'WritPath') {
    Write-Host "This folder is called '$name'. WoW needs it to be called 'WritPath':"
    Write-Host "close the game, rename $addonDir to WritPath, then run Setup Updater.bat again."
    Read-Host 'Press Enter to close' | Out-Null; exit 1
  }
  if ((Split-Path -Leaf $addOns) -ne 'AddOns') {
    Write-Host "WritPath should be inside your game's Interface\AddOns folder; it's in $addOns."
    Read-Host 'Press Enter to close' | Out-Null; exit 1
  }
  $home_ = Join-Path $env:LOCALAPPDATA 'WritPath'
  New-Item -ItemType Directory -Force -Path $home_ | Out-Null
  Set-Content -Path (Join-Path $home_ 'config.txt') -Value $addOns
  $updater = Join-Path $home_ 'update-writpath.ps1'
  Copy-Item (Join-Path $PSScriptRoot 'update-writpath.ps1') $updater -Force

  $shell = New-Object -ComObject WScript.Shell
  $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
  $icon = Join-Path $addonDir 'Media\icon.ico'
  # desktop: update now, with a window that says what happened
  $desk = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'Update WritPath.lnk'))
  $desk.TargetPath = $ps
  $desk.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$updater`""
  $desk.Description = 'Install the newest WritPath'
  if (Test-Path $icon) { $desk.IconLocation = $icon }
  $desk.Save()
  # Windows logon: the same, quietly
  $start = $shell.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Startup')) 'WritPath updater.lnk'))
  $start.TargetPath = $ps
  $start.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$updater`" -Quiet"
  $start.WindowStyle = 7
  $start.Description = 'Checks for a new WritPath at logon'
  $start.Save()

  Write-Host 'WritPath updater is set up:'
  Write-Host '  - "Update WritPath" on your desktop installs the newest version (then /reload in game)'
  Write-Host '  - it also checks by itself each time you log in to Windows'
  Write-Host "  - AddOns folder: $addOns"
  Write-Host ''
  $now = Read-Host 'Check for an update now? (Y/n)'
  if ($now -ne 'n' -and $now -ne 'N') { & $ps -NoProfile -ExecutionPolicy Bypass -File $updater }
} catch {
  Write-Host ("Setup failed: " + $_.Exception.Message)
  Read-Host 'Press Enter to close' | Out-Null
  exit 1
}
