# vault

> SSH host list synced via Gitea. Works on **Windows, macOS, Linux**.

## Quick start (new machine)

### Windows
Clone o projeto: para dentro de .ssh na sua pasta de usuario

Open PowerShell, then:

```powershell
# one-time: allow running local .ps1 scripts in this user
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# extract the tar.gz you got from your team / yourself
tar xzf vault-repo.tar.gz -C $env:USERPROFILE\.ssh\vault --force
cd $env:USERPROFILE\.ssh\vault

# run the wizard
powershell -ExecutionPolicy Bypass -File .\scripts\setup.ps1
```

### Linux / macOS

```bash
tar xzf vault-repo.tar.gz -C ~/.ssh/vault --force
cd ~/.ssh/vault
./scripts/setup.sh
```

The wizard will:
1. Clone (or reuse) the vault repo at `~/.ssh/vault`
2. Install `sshvault` in your PATH
3. Set up your private SSH key (generate new, or restore from backup)
4. Guide you through installing the public key on each server
5. Add hosts to the vault
6. Commit and push everything to Gitea

After setup, use:

```bash
sshvault             # TUI menu
sshvault prod-web    # direct connect
sshvault list        # list all hosts
sshvault add         # add a host
sshvault edit        # edit hosts.toml in $EDITOR
sshvault push "msg"  # commit + push
sshvault pull        # pull from Gitea
```

## What the wizard does, step by step

| Step | What happens |
|------|--------------|
| 1 | Checks git, asks for the Gitea repo URL, clones to `~/.ssh/vault` |
| 2 | Installs `sshvault` to `/usr/local/bin` (Linux/macOS) or adds the repo to PATH (Windows) |
| 3 | Generates a new `ed25519` key — or restores from a backup file you point it at |
| 4 | Loops over servers: asks for `user@host`, runs `install-key-remote` which prompts for the server's password once and installs the public key |
| 5 | Loops over hosts: asks for alias/user/host/port/desc/tags, writes to `hosts.toml` |
| 6 | `git add -A && git commit && git push` — your hosts are now in Gitea |

## Files in this repo

```
.
├── sshvault              # binary (Linux x86_64)
├── sshvault.exe          # binary (Windows)
├── sshvault.cmd          # Windows wrapper
├── hosts.toml            # the list of hosts
├── scripts/
│   ├── setup.sh / setup.ps1          # interactive wizard (start here)
│   ├── diagnose-remote.sh            # debug a server's ssh config
│   ├── fix-remote.sh                 # repair authorized_keys on a server
│   ├── local/install-key.sh / .ps1   # install private key locally
│   └── remote/install-key-remote.sh / .ps1  # install pub key on server
└── README.md
```

## Setting up a new server (after the initial setup)

```bash
# 1. add the server's public key (asks for password once)
./scripts/remote/install-key-remote.sh deploy@10.0.1.10

# 2. add the host
sshvault add
# (alias, user, host, port, desc, tags)

# 3. sync
sshvault push "added new server"
```

## Setting up a new machine (after the first)

```bash
# clone the vault
git clone git@git.seudominio.com:user/vault.git ~/.ssh/vault
cd ~/.ssh/vault

# run the wizard — it will let you restore a key from a backup
./scripts/setup.sh
```

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `sshvault: command not found` | Open a new terminal (PATH was just changed) |
| `Permission denied (publickey)` after install-key-remote | Run `./scripts/diagnose-remote.sh user@host` |
| `PubkeyAuthentication no` in server config | Need root on the server to edit `/etc/ssh/sshd_config` |
| Windows: `running scripts is disabled` | `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser` |
| Windows: `cannot be loaded, not digitally signed` | Prefix with `powershell -ExecutionPolicy Bypass -File ...` |

## Security notes

- Repo must be **private** — it has IP addresses and metadata
- Never commit the private key to this repo
- Keep a backup of `id_ed25519` somewhere safe (password manager, encrypted USB)
- Rotate keys every 6-12 months
