# install-key.ps1  (Windows 10/11)
# Installs the SSH private key in the right place and configures ssh-agent.
#
# Usage:
#   .\install-key.ps1                          # generates new key + installs
#   .\install-key.ps1 -KeyPath C:\keys\id_key  # installs existing key
#   .\install-key.ps1 -AgentOnly               # only adds to the agent
[CmdletBinding()]
param(
    [string]$KeyPath = "",
    [switch]$AgentOnly
)

# Force UTF-8 output (avoid encoding issues with non-ASCII chars)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$ErrorActionPreference = "Stop"
function Note($m) { Write-Host "-> $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "[OK] $m" -ForegroundColor Green }
function Die($m)  { Write-Host "[X] $m" -ForegroundColor Red; exit 1 }
function NewEd25519KeyNoPass($path) {
    # Empty-passphrase handling differs by PowerShell edition: PS 7+ passes
    # -N "" as a real empty string, Windows PowerShell 5.1 needs -N '""'.
    # Getting it wrong bakes a literal 2-char passphrase into the key.
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        ssh-keygen -t ed25519 -f $path -N "" -q
    } else {
        ssh-keygen -t ed25519 -f $path -N '""' -q
    }
}

# --- paths ---
$sshDir  = Join-Path $env:USERPROFILE ".ssh"
$keyPath = Join-Path $sshDir "id_ed25519"
$pubPath = Join-Path $sshDir "id_ed25519.pub"

if (-not (Test-Path $sshDir)) {
    New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    # use simple permission reset that works on every Windows version
    & icacls $sshDir /inheritance:r /grant:r "${env:USERNAME}:(R,W)" | Out-Null
}

# --- 1. ensure ssh-agent service ---
Note "ensuring ssh-agent service"
Set-Service ssh-agent -StartupType Automatic -ErrorAction SilentlyContinue
Start-Service ssh-agent -ErrorAction SilentlyContinue
$svc = Get-Service ssh-agent
if ($svc.Status -ne "Running") { Die "ssh-agent service is $($svc.Status)" }
Ok "ssh-agent running"

# --- 2. ensure key exists ---
if (-not $AgentOnly) {
    if ($KeyPath) {
        if (-not (Test-Path $KeyPath)) { Die "key not found: $KeyPath" }
        Note "copying $KeyPath -> $keyPath"
        Copy-Item $KeyPath $keyPath -Force
    } elseif (-not (Test-Path $keyPath)) {
        Note "generating new ed25519 key (no passphrase)"
        NewEd25519KeyNoPass $keyPath
        if ($LASTEXITCODE -ne 0) { Die "ssh-keygen failed" }
    } else {
        Note "using existing $keyPath"
    }
    & icacls $keyPath /inheritance:r /grant:r "${env:USERNAME}:(R)" | Out-Null
    if (-not (Test-Path $pubPath)) {
        $pubRaw = ssh-keygen -y -f $keyPath
        if ($LASTEXITCODE -ne 0) { Die "ssh-keygen -y failed" }
        Set-Content -Path $pubPath -Value $pubRaw
    }
    Ok "key: $keyPath"
    Ok "pub: $pubPath"
}

# --- 3. add to agent ---
Note "ssh-add $keyPath"
& ssh-add $keyPath 2>&1 | ForEach-Object { Write-Host "  $_" }
if ($LASTEXITCODE -ne 0) { Die "ssh-add failed" }
Ok "key loaded into agent"

# --- 4. vault skeleton ---
$vaultDir = Join-Path $sshDir "vault"
if (-not (Test-Path $vaultDir)) {
    Note "creating $vaultDir"
    New-Item -ItemType Directory -Path $vaultDir -Force | Out-Null
    $hostsFile = Join-Path $vaultDir "hosts.toml"
    if (-not (Test-Path $hostsFile)) {
        @"
# hosts.toml - add your servers here, then run `sshvault push`
# Example:
# [hosts.prod-web]
# user = "deploy"
# host = "10.0.1.10"
# port = 22
# desc = "Frontend production"
# tags = ["prod", "web"]
"@ | Set-Content -Path $hostsFile
    }
    Ok "vault skeleton created"
}

# --- 5. print public key ---
Write-Host ""
Write-Host "===================================================" -ForegroundColor DarkGray
Write-Host "Your public key (copy this to the server's authorized_keys):" -ForegroundColor Yellow
Write-Host ""
Get-Content $pubPath | ForEach-Object { Write-Host "  $_" -ForegroundColor White }
Write-Host ""
Write-Host "===================================================" -ForegroundColor DarkGray
Write-Host ""
Ok "done. next step:"
Write-Host "  .\scripts\remote\install-key-remote.ps1 user@host" -ForegroundColor Cyan
