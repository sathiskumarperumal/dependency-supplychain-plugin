<#
.SYNOPSIS
    Docker-free bootstrap for the Dependency & Supply-Chain plugin on Windows.

.DESCRIPTION
    Installs NATIVE Syft + Grype binaries on PATH (downloaded from the anchore GitHub releases).
    OWASP Dependency-Check needs no install — it runs via the Maven plugin. Java 17+ and Maven must
    already be present. No Docker, no images, no daemon.

.PARAMETER BinDir
    Where the binaries are installed. Default: %USERPROFILE%\.depscan\bin
#>
[CmdletBinding()]
param(
    [string]$BinDir = "$env:USERPROFILE\.depscan\bin"
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null

Write-Host "== Dependency & Supply-Chain plugin - native setup (no Docker) ==" -ForegroundColor Cyan

function Install-AnchoreTool([string]$Name) {
    $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/anchore/$Name/releases/latest" -Headers @{ 'User-Agent' = 'depscan-setup' }
    $asset = $rel.assets | Where-Object { $_.name -match '_windows_amd64\.zip$' } | Select-Object -First 1
    if (-not $asset) { throw "No Windows asset found for $Name" }
    $zip = Join-Path $env:TEMP $asset.name
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -Headers @{ 'User-Agent' = 'depscan-setup' }
    Expand-Archive -Path $zip -DestinationPath $BinDir -Force
    Remove-Item $zip -Force
    Write-Host "$Name installed -> $BinDir" -ForegroundColor Green
}

Install-AnchoreTool 'syft'
Install-AnchoreTool 'grype'

# Prerequisite checks (advisory)
if (-not (Get-Command java -ErrorAction SilentlyContinue)) { Write-Warning "Java not found — install a JDK 17+." }
if (-not (Get-Command mvn  -ErrorAction SilentlyContinue)) { Write-Warning "Maven not found — install Maven (or use .\mvnw)." }

# Add BinDir to user PATH
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath -notlike "*$BinDir*") {
    [Environment]::SetEnvironmentVariable('Path', "$userPath;$BinDir", 'User')
    Write-Host "Added $BinDir to user PATH - restart your shell to pick it up." -ForegroundColor Yellow
} else {
    Write-Host "$BinDir already on user PATH." -ForegroundColor DarkGray
}

Write-Host "`nSetup complete (no Docker)." -ForegroundColor Cyan
Write-Host "  - Verify with: /depscan-doctor" -ForegroundColor Gray
Write-Host "  - Optional: set NVD_API_KEY to speed up OWASP Dependency-Check." -ForegroundColor DarkGray
Write-Host "  - Local Claude Code use also needs MCP token vars (GITHUB_PERSONAL_ACCESS_TOKEN, ATLASSIAN_API_TOKEN)." -ForegroundColor DarkGray
