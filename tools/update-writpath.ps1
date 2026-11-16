# WritPath updater: installs the newest WritPath from GitHub when there is one.
#   -Quiet   no window output and no pause (used at Windows logon); writes update.log instead
# Your settings and learned data live in WTF\...\SavedVariables, which this never touches.
param([switch]$Quiet)

$ErrorActionPreference = 'Stop'
$Repo    = 'eekanti/WritPath'
$Home_   = Join-Path $env:LOCALAPPDATA 'WritPath'
$Config  = Join-Path $Home_ 'config.txt'      # the AddOns folder
$Stamp   = Join-Path $Home_ 'installed.txt'   # the GitHub commit installed last
$Log     = Join-Path $Home_ 'update.log'
New-Item -ItemType Directory -Force -Path $Home_ | Out-Null

function Say($msg) {
  Add-Content -Path $Log -Value ("{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $msg)
  if (-not $Quiet) { Write-Host $msg }
}
function Done($code) {
  if (-not $Quiet) { Write-Host ''; Read-Host 'Press Enter to close' | Out-Null }
  exit $code
}
function TocVersion($dir) {
  $toc = Join-Path $dir 'WritPath.toc'
  if (Test-Path $toc) {
    $line = Select-String -Path $toc -Pattern '^## Version:\s*(.+)$' | Select-Object -First 1
    if ($line) { return $line.Matches[0].Groups[1].Value.Trim() }
  }
  return '?'
}

try {
  if (-not (Test-Path $Config)) { Say 'WritPath updater is not set up yet: run "Setup Updater.bat" in WritPath\tools once.'; Done 1 }
  $AddOns = (Get-Content $Config -TotalCount 1).Trim()
  $Target = Join-Path $AddOns 'WritPath'
  if (-not (Test-Path $AddOns)) { Say "AddOns folder not found: $AddOns (run Setup Updater.bat again)."; Done 1 }
  # a git checkout is a developer's copy: never overwrite it
  if (Test-Path (Join-Path $Target '.git')) { Say "$Target is a git checkout: update it with git pull instead."; Done 1 }

  $headers = @{ 'User-Agent' = 'WritPath-updater'; 'Accept' = 'application/vnd.github+json' }
  $commit = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/commits/main" -Headers $headers -TimeoutSec 20
  $sha = $commit.sha
  $have = if (Test-Path $Stamp) { (Get-Content $Stamp -TotalCount 1).Trim() } else { '' }
  $before = TocVersion $Target
  if ($sha -eq $have -and (Test-Path (Join-Path $Target 'WritPath.toc'))) {
    Say "WritPath $before is up to date."
    Done 0
  }

  $tmp = Join-Path $env:TEMP ("WritPath-update-" + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  try {
    $zip = Join-Path $tmp 'WritPath.zip'
    Invoke-WebRequest -Uri "https://codeload.github.com/$Repo/zip/$sha" -OutFile $zip -Headers $headers -UseBasicParsing -TimeoutSec 120
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $src = Get-ChildItem -Path $tmp -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'WritPath.toc') } | Select-Object -First 1
    if (-not $src) { throw 'the download has no WritPath.toc' }
    $after = TocVersion $src.FullName
    New-Item -ItemType Directory -Force -Path $Target | Out-Null
    # mirror: the folder ends up exactly like the release (old files removed)
    robocopy $src.FullName $Target /MIR /NFL /NDL /NJH /NJS /NP /R:2 /W:1 | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "copying into $Target failed (robocopy $LASTEXITCODE): is the folder writable?" }
    # the updater updates itself too
    $newSelf = Join-Path $src.FullName 'tools\update-writpath.ps1'
    if (Test-Path $newSelf) { Copy-Item $newSelf (Join-Path $Home_ 'update-writpath.ps1') -Force }
    Set-Content -Path $Stamp -Value $sha
    Say "WritPath updated: $before -> $after. In game: /reload (or restart the game if it says new files were added)."
  } finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
  }
  Done 0
} catch {
  Say ("Update failed: " + $_.Exception.Message)
  Done 1
}
