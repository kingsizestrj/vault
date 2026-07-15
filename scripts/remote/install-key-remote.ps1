# install-key-remote.ps1  (Windows 10/11)
# Installs the public key on a remote server.
# Tries ssh-copy-id first; falls back to manual cat | ssh.
#
# Usage:
#   .\install-key-remote.ps1 user@host
#   .\install-key-remote.ps1 user@host -Port 2222
#   .\install-key-remote.ps1 user@host -KeyPath C:\keys\id_ed25519.pub
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Target,

    [int]$Port = 0,
    [string]$KeyPath = ""
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
# DO NOT use $ErrorActionPreference = "Stop"

function Note($m) { Write-Host "-> $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "[OK] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "[!] $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "[X] $m" -ForegroundColor Red; exit 1 }

# --- pick key ---
if (-not $KeyPath) {
    $sshBase = Join-Path $env:USERPROFILE ".ssh"
    foreach ($name in @("id_ed25519.pub", "id_rsa.pub", "id_ecdsa.pub")) {
        $c = Join-Path $sshBase $name
        if (Test-Path $c) { $KeyPath = $c; break }
    }
}
if (-not (Test-Path $KeyPath)) { Die "no public key found (use -KeyPath)" }
Note "public key: $KeyPath"

# --- base SSH options ---
function Get-SshBaseArgs {
    $args = @(
        "-o", "StrictHostKeyChecking=accept-new",
        "-o", "ConnectTimeout=10"
    )
    if ($Port) { $args += @("-p", "$Port") }
    return ,$args
}

function Invoke-Ssh {
    param([string[]]$Extra)
    $base = Get-SshBaseArgs
    $all = $base + $Extra
    $output = & ssh @all 2>&1
    $code = $LASTEXITCODE
    if ($null -eq $code) { $code = 1 }
    return @{ Code = $code; Output = $output }
}

# --- 1. test if key already works ---
Note "checking existing key auth to $Target"
$r = Invoke-Ssh -Extra @("-o", "BatchMode=yes", "-o", "PasswordAuthentication=no", $Target, "true")
if ($r.Code -eq 0) {
    Ok "key already installed on $Target - nothing to do"
    return
}
$firstLine = ($r.Output | Select-Object -First 1) -as [string]
Note "key not yet installed (server said: $firstLine)"

# --- 2. try ssh-copy-id ---
$copyIdRan = $false
$sshCopyId = Get-Command ssh-copy-id -ErrorAction SilentlyContinue
if ($sshCopyId) {
    Note "trying ssh-copy-id at $($sshCopyId.Source)"
    try {
        $base = Get-SshBaseArgs
        $argList = $base + @("-i", $KeyPath, $Target)
        $proc = Start-Process -FilePath ssh-copy-id -ArgumentList $argList -NoNewWindow -Wait -PassThru
        if ($proc.ExitCode -eq 0) {
            $copyIdRan = $true
        } else {
            Note "ssh-copy-id exited with code $($proc.ExitCode), falling back to manual"
        }
    } catch {
        Note "ssh-copy-id failed to run ($($_.Exception.Message)), falling back to manual"
    }
} else {
    Note "ssh-copy-id not found in PATH, using manual install"
}

# --- 3. manual fallback ---
if (-not $copyIdRan) {
    Note "installing key manually (will prompt for password ONCE)"
    $pubContent = (Get-Content $KeyPath -Raw).Trim()
    $pubEscaped = $pubContent -replace "'", "'\\''"
    $remoteCmd = "mkdir -p ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && grep -qxF '$pubEscaped' ~/.ssh/authorized_keys || echo '$pubEscaped' >> ~/.ssh/authorized_keys && echo __SSHVAULT_KEY_INSTALLED__"

    $base = Get-SshBaseArgs
    $argList = $base + @($Target, $remoteCmd)
    $proc = Start-Process -FilePath ssh -ArgumentList $argList -NoNewWindow -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        Die "manual key install failed (exit code $($proc.ExitCode))"
    }
}

# --- 4. verify ---
Note "verifying key auth (this should NOT ask for a password)"
$r = Invoke-Ssh -Extra @("-o", "BatchMode=yes", "-v", $Target, "true")
if ($r.Code -eq 0) {
    Ok "key installed on $Target - next time: ssh $Target"
    return
}

# verification failed — show the real reason
Warn "key verification FAILED. server output:"
$r.Output | ForEach-Object { Write-Host "    $_" }
Write-Host ""
Warn "common causes:"
Write-Host "  - server has PasswordAuthentication=yes but PubkeyAuthentication=no"
Write-Host "  - server has AuthorizedKeysFile pointing to a wrong file"
Write-Host "  - ~/.ssh or ~/.ssh/authorized_keys have wrong permissions on the server"
Write-Host "  - server requires a specific key type (e.g. only RSA, not ed25519)"
Write-Host ""
Warn "to debug, run manually:"
Write-Host "  ssh -vvv $Target true" -ForegroundColor White
Write-Host ""
Die "verification failed"
