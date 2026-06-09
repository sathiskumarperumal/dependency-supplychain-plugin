<#
.SYNOPSIS
    One-time bootstrap for the Dependency & Supply-Chain plugin on a Windows machine.

.DESCRIPTION
    Makes the plugin portable: instead of installing Grype / Syft / OWASP Dependency-Check
    natively, it installs thin Docker wrappers on PATH and pre-pulls the scanner images.
    After this runs, the only host prerequisite for scanning is Docker.

    Steps:
      1. Verify Docker is installed and the daemon is running.
      2. Pre-pull anchore/grype, anchore/syft, owasp/dependency-check.
      3. Create named volumes that cache the vulnerability DBs across runs.
      4. Copy the *.cmd wrappers to a bin dir and add it to the user PATH.

.PARAMETER BinDir
    Where the wrappers are installed. Default: %USERPROFILE%\.depscan\bin
#>
[CmdletBinding()]
param(
    [string]$BinDir = "$env:USERPROFILE\.depscan\bin"
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "== Dependency & Supply-Chain plugin - setup ==" -ForegroundColor Cyan

# 1. Docker present and running? --------------------------------------------
try { docker --version | Out-Null }
catch { throw "Docker not found on PATH. Install Docker Desktop, then re-run this script." }
try { docker info 2>$null | Out-Null }
catch { throw "Docker is installed but the daemon is not running. Start Docker Desktop and re-run." }
Write-Host "Docker OK" -ForegroundColor Green

# 2. Pre-pull scanner images ------------------------------------------------
$images = @('anchore/grype:latest', 'anchore/syft:latest', 'owasp/dependency-check:latest')
foreach ($img in $images) {
    Write-Host "Pulling $img ..." -ForegroundColor DarkGray
    docker pull $img | Out-Null
}
Write-Host "Images ready" -ForegroundColor Green

# 3. Create DB cache volumes ------------------------------------------------
foreach ($vol in @('depscan-grype-db', 'depscan-dc-data')) {
    docker volume create $vol | Out-Null
}

# 4. Install wrappers on PATH -----------------------------------------------
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
Copy-Item (Join-Path $ScriptDir '*.cmd') -Destination $BinDir -Force
Write-Host "Wrappers installed to $BinDir" -ForegroundColor Green

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath -notlike "*$BinDir*") {
    [Environment]::SetEnvironmentVariable('Path', "$userPath;$BinDir", 'User')
    Write-Host "Added $BinDir to user PATH - restart your shell to pick it up." -ForegroundColor Yellow
} else {
    Write-Host "$BinDir already on user PATH." -ForegroundColor DarkGray
}

Write-Host "`nSetup complete." -ForegroundColor Cyan
Write-Host "Next:" -ForegroundColor Cyan
Write-Host "  1. Set the MCP token env vars (User scope), e.g.:" -ForegroundColor Gray
Write-Host '     [Environment]::SetEnvironmentVariable("GITHUB_PERSONAL_ACCESS_TOKEN","<pat>","User")' -ForegroundColor DarkGray
Write-Host "     (also ATLASSIAN_API_TOKEN, SONARQUBE_TOKEN; optional NVD_API_KEY)" -ForegroundColor DarkGray
Write-Host "  2. Restart your shell, then run /depscan-doctor to verify." -ForegroundColor Gray
