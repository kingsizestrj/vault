# setup.ps1  (Windows 10/11)
# One-shot setup wizard. Run this on a fresh machine and answer the prompts.
#
# What it does:
#   1. Asks for the Gitea repo URL, clones it to ~/.ssh/vault
#   2. Installs sshvault.exe in your PATH
#   3. Sets up the local SSH key (generate new OR restore from backup)
#   4. Guides you through installing the public key on remote servers
#   5. Adds hosts to the vault
#   6. Pushes everything to Gitea
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\scripts\setup.ps1
[CmdletBinding()]
param()

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

# -- colors / helpers -------------------------------------
function Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  +----------------------------------------------+" -ForegroundColor Magenta
    Write-Host "  |  sshvault setup wizard                        |" -ForegroundColor Magenta
    Write-Host "  |  Gitea-synced SSH host manager                |" -ForegroundColor DarkGray
    Write-Host "  +----------------------------------------------+" -ForegroundColor Magenta
    Write-Host ""
}
function Step($n, $title) {
    Write-Host ""
    Write-Host "-- step $n : $title --" -ForegroundColor Cyan
    Write-Host ""
}
function Note($m)   { Write-Host "  -> $m" -ForegroundColor Cyan }
function Ok($m)     { Write-Host "  [OK] $m" -ForegroundColor Green }
function Warn($m)   { Write-Host "  [!] $m" -ForegroundColor Yellow }
function Die($m)    { Write-Host "  [X] $m" -ForegroundColor Red; exit 1 }
function Ask($q, $default = "") {
    if ($default) {
        Write-Host "  ? $q [$default]: " -ForegroundColor Yellow -NoNewline
    } else {
        Write-Host "  ? ${q}: " -ForegroundColor Yellow -NoNewline
    }
    $ans = Read-Host
    if ([string]::IsNullOrWhiteSpace($ans)) { return $default }
    return $ans.Trim()
}
function AskYesNo($q, $defaultYes = $true) {
    $yn = if ($defaultYes) { "Y/n" } else { "y/N" }
    Write-Host "  ? $q [$yn]: " -ForegroundColor Yellow -NoNewline
    $ans = Read-Host
    if ([string]::IsNullOrWhiteSpace($ans)) { return $defaultYes }
    return $ans -match "^[yY]"
}
function AskPassword($q) {
    Write-Host "  ? ${q}: " -ForegroundColor Yellow -NoNewline
    $pwd = Read-Host -AsSecureString
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($pwd)
    return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
}

Banner

# -- step 1 : git + repo URL -----------------------------
Step 1 "git + repo"
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Die "git not found in PATH. Install Git for Windows: https://git-scm.com/download/win"
}
Ok "git found: $((Get-Command git).Source)"

# sshvault dir lives at ~/.ssh/vault
$sshDir  = Join-Path $env:USERPROFILE ".ssh"
$vault   = Join-Path $sshDir "vault"
$exe     = Join-Path $vault "sshvault.exe"
$wrapper = Join-Path $vault "sshvault.cmd"

if (Test-Path $vault) {
    Warn "$vault already exists"
    if (-not (AskYesNo "reuse it?")) {
        Die "move it away and run setup again"
    }
} else {
    $repo = Ask "Gitea repo URL (e.g. git@git.seudominio.com:user/vault.git)"
    if (-not $repo) { Die "repo URL required" }
    Note "cloning $repo -> $vault"
    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
        & icacls $sshDir /inheritance:r /grant:r "${env:USERNAME}:(R,W)" | Out-Null
    }
    git clone $repo $vault
    if ($LASTEXITCODE -ne 0) { Die "git clone failed" }
    Ok "cloned"
}

Set-Location $vault

# make sure sshvault.exe + sshvault.cmd are present (they should be from the repo)
if (-not (Test-Path $exe)) { Die "sshvault.exe missing in repo - re-extract the tarball" }
if (-not (Test-Path $wrapper)) { Die "sshvault.cmd missing in repo - re-extract the tarball" }
Ok "sshvault.exe present"

# -- step 2 : PATH ----------------------------------------
Step 2 "PATH"
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -like "*$vault*") {
    Ok "PATH already includes $vault"
} else {
    Note "adding $vault to your PATH"
    [Environment]::SetEnvironmentVariable("Path", "$userPath;$vault", "User")
    $env:Path = "$env:Path;$vault"
    Ok "done - close and reopen PowerShell if 'sshvault' isn't found"
}

# verify sshvault is callable
$which = Get-Command sshvault -ErrorAction SilentlyContinue
if ($which) {
    Ok "sshvault callable: $($which.Source)"
} else {
    Warn "sshvault not yet callable in this session - will work after restart"
}

# -- step 3 : local SSH key -------------------------------
Step 3 "local SSH key"
$keyPath = Join-Path $sshDir "id_ed25519"
$pubPath = Join-Path $sshDir "id_ed25519.pub"

if (Test-Path $keyPath) {
    Ok "key already exists at $keyPath (skipping generation)"
} else {
    Write-Host ""
    Write-Host "  Choose how to set up your private key:" -ForegroundColor White
    Write-Host "    1) Generate a new ed25519 key (no passphrase, recommended)" -ForegroundColor Gray
    Write-Host "    2) Generate a new ed25519 key WITH a passphrase" -ForegroundColor Gray
    Write-Host "    3) Restore from a backup file (you have a copy of the key)" -ForegroundColor Gray
    $choice = Ask "choice [1]"
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "1" }
    switch ($choice) {
        "3" {
            $backup = Ask "path to backup key (e.g. C:\keys\id_ed25519)"
            if (-not (Test-Path $backup)) { Die "not found: $backup" }
            Note "installing $backup -> $keyPath"
            Copy-Item $backup $keyPath -Force
            & icacls $keyPath /inheritance:r /grant:r "${env:USERNAME}:(R)" | Out-Null
            if (-not (Test-Path $pubPath)) {
                $pub = ssh-keygen -y -f $keyPath
                Set-Content -Path $pubPath -Value $pub
            }
        }
        "2" {
            Note "generating key (you will be asked for a passphrase)"
            $pass = AskPassword "passphrase (empty for none)"
            ssh-keygen -t ed25519 -f $keyPath -N $pass
        }
        default {
            Note "generating key with no passphrase"
            ssh-keygen -t ed25519 -f $keyPath -N '""' -q
        }
    }
    if ($LASTEXITCODE -ne 0) { Die "key setup failed" }
    & icacls $keyPath /inheritance:r /grant:r "${env:USERNAME}:(R)" | Out-Null
    Ok "private key: $keyPath"
    Ok "public key:  $pubPath"
}

# ensure ssh-agent is running and key is loaded
Set-Service ssh-agent -StartupType Automatic -ErrorAction SilentlyContinue
Start-Service ssh-agent -ErrorAction SilentlyContinue
try { ssh-add $keyPath 2>&1 | Out-Null } catch { }  # suppress native-exe noise on success
if ($LASTEXITCODE -ne 0) { Die "ssh-add failed (exit $LASTEXITCODE)" }
Ok "key loaded into ssh-agent"

# -- step 4 : install public key on remote server(s) ------
Step 4 "install public key on remote server(s)"
Write-Host ""
Write-Host "  For each server, you'll be asked for:" -ForegroundColor Gray
Write-Host "    - user@host (e.g. deploy@10.0.1.10)" -ForegroundColor Gray
Write-Host "    - port (default 22)" -ForegroundColor Gray
Write-Host "  The script will prompt for the server's password ONCE," -ForegroundColor Gray
Write-Host "  install the public key, and verify it works." -ForegroundColor Gray
Write-Host ""

while ($true) {
    $target = Ask "user@host to set up (blank to skip / finish)"
    if ([string]::IsNullOrWhiteSpace($target)) { break }
    $port = Ask "port [22]"
    $portArg = @()
    if ($port) { $portArg = @("-Port", $port) }
    powershell -ExecutionPolicy Bypass -File "$vault\scripts\remote\install-key-remote.ps1" @portArg $target
    if ($LASTEXITCODE -ne 0) {
        Warn "install on $target returned non-zero - fix it and re-run setup later"
    }
    if (-not (AskYesNo "set up another server?")) { break }
}

# -- step 5 : add hosts to vault --------------------------
Step 5 "add hosts to the vault"
Write-Host ""
Write-Host "  Now let's add hosts. For each one, answer the prompts." -ForegroundColor Gray
Write-Host "  (Leave 'alias' blank to stop.)" -ForegroundColor Gray
Write-Host ""

while ($true) {
    Note "adding a host (leave alias blank to finish)"
    $alias = Ask "alias (e.g. prod-web)"
    if ([string]::IsNullOrWhiteSpace($alias)) { break }
    $user = Ask "ssh user [root]"
    if (-not $user) { $user = "root" }
    $host_ = Ask "hostname or IP (e.g. 10.0.1.10)"
    if (-not $host_) { Warn "hostname required, skipping"; continue }
    $port = Ask "port [22]"
    $desc = Ask "description"
    $tags = Ask "tags (comma separated, e.g. prod,web,critical)"

    # build and save
    $vaultDir = $vault
    $hostsFile = Join-Path $vaultDir "hosts.toml"
    if (-not (Test-Path $hostsFile)) {
        "# hosts.toml" | Set-Content $hostsFile
    }

    $portNum = 22
    if ($port) { [int]::TryParse($port, [ref]$portNum) | Out-Null }
    if ($portNum -eq 0) { $portNum = 22 }

    # build TOML block using a regular double-quoted string so the
    # $alias / $user / etc. variables are expanded by PowerShell
    # (a here-string @"..."@ would treat them as literal text).
    $lines = @()
    $lines += "[hosts.$alias]"
    $lines += "user = `"$user`""
    $lines += "host = `"$host_`""
    $lines += "port = $portNum"
    if ($desc) { $lines += "desc = `"$desc`"" }
    if ($tags) {
        $tagsArr = @()
        foreach ($t in ($tags -split ',')) {
            $t = $t.Trim()
            if ($t) { $tagsArr += "`"$t`"" }
        }
        $joined = $tagsArr -join ", "
        $lines += "tags = [$joined]"
    }
    $tomlBlock = ($lines -join "`n") + "`n"

    Add-Content -Path $hostsFile -Value $tomlBlock
    Ok "added: $alias"
}

# -- step 6 : commit + push -------------------------------
Step 6 "sync to Gitea"
$status = git status --porcelain
if (-not $status) {
    Note "no changes to commit"
} else {
    $msg = Ask "commit message [update vault]" "update vault"
    git add -A
    git commit -q -m $msg
    if ($LASTEXITCODE -ne 0) { Die "git commit failed" }
    Ok "committed"
    Note "pushing to Gitea..."
    git push
    if ($LASTEXITCODE -ne 0) { Warn "git push failed - run 'sshvault push' later to retry" }
    else { Ok "pushed" }
}

# -- done -------------------------------------------------
Step "done!"
Write-Host "  Everything is set up. Try:" -ForegroundColor Green
Write-Host ""
Write-Host "    sshvault             " -NoNewline; Write-Host "# open the TUI" -ForegroundColor Gray
Write-Host "    sshvault list        " -NoNewline; Write-Host "# see all hosts" -ForegroundColor Gray
Write-Host "    sshvault <alias>     " -NoNewline; Write-Host "# connect directly" -ForegroundColor Gray
Write-Host ""
Write-Host "  On other machines, just run this setup.ps1 again with the same repo." -ForegroundColor Cyan
Write-Host ""
