#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# bootstrap.sh  (Linux / macOS)
# Cria a estrutura do vault no Gitea (1 vez só, na primeira máquina).
#
# Pré-requisitos: git + acesso SSH ao seu Gitea.
#
# Uso:
#   ./bootstrap.sh git@git.seudominio.com:user/vault.git
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
set -euo pipefail

[ $# -ge 1 ] || { sed -n '2,9p' "$0"; exit 1; }
REPO="$1"
WORK="$HOME/.ssh/vault"
GIT_NAME="${GIT_NAME:-$(git config --global user.name 2>/dev/null || echo 'sshvault')}"
GIT_EMAIL="${GIT_EMAIL:-$(git config --global user.email 2>/dev/null || echo 'sshvault@local')}"

note() { echo "→ $*"; }
ok()   { echo "✓ $*"; }
die()  { echo "✗ $*" >&2; exit 1; }

# ─── 1. ensure ~/.ssh ────────────────────────────
mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"

# ─── 2. clone or init ────────────────────────────
if [ -d "$WORK" ]; then
  die "$WORK already exists — remove it first or use sshvault pull"
fi

if git ls-remote "$REPO" >/dev/null 2>&1; then
  note "cloning existing repo $REPO"
  git clone "$REPO" "$WORK"
else
  note "repo not found at $REPO — creating a new local one (you push it manually)"
  mkdir -p "$WORK"
  cd "$WORK"
  git init -q
  git config user.name "$GIT_NAME"
  git config user.email "$GIT_EMAIL"
fi

cd "$WORK"

# ─── 3. write skeleton files ─────────────────────
if [ ! -f hosts.toml ]; then
cat > hosts.toml <<'EOF'
# hosts.toml — my SSH vault
# Run `sshvault add` to add hosts interactively,
# or edit this file directly. Then `sshvault push`.

# [hosts.prod-web]
# user = "deploy"
# host = "10.0.1.10"
# port = 22
# desc = "Frontend production"
# tags = ["prod", "web"]
EOF
fi

if [ ! -f README.md ]; then
cat > README.md <<'EOF'
# My SSH Vault

Synced SSH host list. Edit `hosts.toml`, then run:

```bash
sshvault push "added new server"
```

On another machine:

```bash
sshvault pull
```
EOF
fi

# ─── 4. initial commit + push ────────────────────
git add -A
git status --porcelain | head -5
if git diff --cached --quiet; then
  note "nothing to commit"
else
  git commit -q -m "initial vault"
  ok "committed"
fi

if git remote get-url origin >/dev/null 2>&1; then
  note "pushing to origin"
  git push -u origin "$(git rev-parse --abbrev-ref HEAD)"
else
  note "no remote configured — set one with:"
  echo "    git -C $WORK remote add origin $REPO"
  echo "    git -C $WORK push -u origin main"
fi

ok "vault ready at $WORK"
echo ""
echo "Next steps:"
echo "  1. install local key:  ./scripts/local/install-key.sh"
echo "  2. install on server:  ./scripts/remote/install-key-remote.sh user@host"
echo "  3. add a host:         sshvault add"
echo "  4. sync:               sshvault push"
