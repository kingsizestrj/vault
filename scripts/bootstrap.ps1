# bootstrap.ps1  (Windows 10/11)
# Creates the vault structure on the first machine.
#
# Usage:
#   .\bootstrap.ps1 git@git.seudominio.com:user/vault.git
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Repo
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

function Note($m) { Write-Host "-> $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "[OK] $m" -ForegroundColor Green }
function Die($m)  { Write-Host "[X] $m" -ForegroundColor Red; exit 1 }

$sshDir  = Join-Path $env:USERPROFILE ".ssh"
$work    = Join-Path $sshDir "vault"
$gitName = git config --global user.name  2>$null
if (-not $gitName) { $gitName = "sshvault" }
$gitEmail = git config --global user.email 2>$null
if (-not $gitEmail) { $gitEmail = "sshvault@local" }

# --- ensure ~/.ssh ---
if (-not (Test-Path $sshDir)) {
    New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    & icacls $sshDir /inheritance:r /grant:r "${env:USERNAME}:(R,W)" | Out-Null
}

# --- clone or init ---
if (Test-Path $work) { Die "$work already exists - remove it first or use sshvault pull" }

$remoteOk = $false
try {
    $null = git ls-remote $Repo 2>$null
    $remoteOk = ($LASTEXITCODE -eq 0)
} catch { $remoteOk = $false }

if ($remoteOk) {
    Note "cloning $Repo -> $work"
    git clone $Repo $work
} else {
    Note "repo $Repo not reachable from here - creating local init (push manually later)"
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    Push-Location $work
    git init -q | Out-Null
    git config user.name $gitName
    git config user.email $gitEmail
    Pop-Location
}

Push-Location $work

# --- write skeleton ---
$hostsFile = "hosts.toml"
if (-not (Test-Path $hostsFile)) {
    @"
# hosts.toml - my SSH vault
# Run `sshvault add` to add hosts interactively,
# or edit this file directly. Then `sshvault push`.

# [hosts.prod-web]
# user = "deploy"
# host = "10.0.1.10"
# port = 22
# desc = "Frontend production"
# tags = ["prod", "web"]
"@ | Set-Content -Path $hostsFile
}

if (-not (Test-Path "README.md")) {
    @"
# My SSH Vault

Synced SSH host list. Edit hosts.toml, then run:

``````powershell
sshvault push 'added new server'
``````

On another machine:

``````powershell
sshvault pull
``````
"@ | Set-Content -Path "README.md"
}

# --- initial commit + push ---
git add -A
$status = git status --porcelain
if ($status) {
    git commit -q -m "initial vault"
    Ok "committed"
} else {
    Note "nothing to commit"
}

$origin = git remote get-url origin 2>$null
if ($origin) {
    Note "pushing to origin"
    $branch = git rev-parse --abbrev-ref HEAD
    git push -u origin $branch
} else {
    Note "no remote configured - set one manually:"
    Write-Host "    cd $work" -ForegroundColor Yellow
    Write-Host "    git remote add origin $Repo" -ForegroundColor Yellow
    Write-Host "    git push -u origin main" -ForegroundColor Yellow
}

Pop-Location

Ok "vault ready at $work"
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. install local key:  .\scripts\local\install-key.ps1" -ForegroundColor White
Write-Host "  2. install on server:  .\scripts\remote\install-key-remote.ps1 user@host" -ForegroundColor White
Write-Host "  3. add a host:         sshvault add" -ForegroundColor White
Write-Host "  4. sync:               sshvault push" -ForegroundColor White
