#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# install-key.sh  (Linux / macOS)
# Instala a chave privada SSH no lugar certo e configura
# o ssh-agent pra não pedir senha toda hora.
#
# Uso:
#   ./install-key.sh                    # gera chave nova + instala
#   ./install-key.sh /caminho/key       # instala chave existente
#   ./install-key.sh --agent-only       # só adiciona no agent
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
set -euo pipefail

AGENT_ONLY=0
KEY_SRC=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent-only) AGENT_ONLY=1; shift ;;
    -h|--help)
      sed -n '2,11p' "$0"; exit 0 ;;
    *) KEY_SRC="$1"; shift ;;
  esac
done

# ─── paths ───────────────────────────────────────
SSH_DIR="$HOME/.ssh"
KEY_PATH="$SSH_DIR/id_ed25519"
PUB_PATH="$SSH_DIR/id_ed25519.pub"
KNOWN_HOSTS="$SSH_DIR/known_hosts"

# ─── helpers ────────────────────────────────────
note() { echo "→ $*"; }
ok()   { echo "✓ $*"; }
die()  { echo "✗ $*" >&2; exit 1; }

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

# ─── 1. ensure ssh-agent is running ─────────────
note "starting ssh-agent"
if ! pgrep -u "$USER" ssh-agent >/dev/null 2>&1; then
  ssh-agent -s | head -2 >> "$SSH_DIR/agent.env"
fi
# shellcheck disable=SC1091
. "$SSH_DIR/agent.env" 2>/dev/null || {
  # fallback: start fresh
  ssh-agent -s | head -2 > "$SSH_DIR/agent.env"
  . "$SSH_DIR/agent.env"
}
ok "agent pid=${SSH_AGENT_PID:-?}"

# ─── 2. ensure the key exists ───────────────────
if [ "$AGENT_ONLY" -eq 0 ]; then
  if [ -n "$KEY_SRC" ]; then
    if [ ! -f "$KEY_SRC" ]; then die "key not found: $KEY_SRC"; fi
    note "copying $KEY_SRC → $KEY_PATH"
    cp "$KEY_SRC" "$KEY_PATH"
    chmod 600 "$KEY_PATH"
  elif [ ! -f "$KEY_PATH" ]; then
    note "generating new ed25519 key (no passphrase = press enter twice)"
    ssh-keygen -t ed25519 -f "$KEY_PATH" -N ""
  else
    note "using existing $KEY_PATH"
  fi
  [ -f "$PUB_PATH" ] || ssh-keygen -y -f "$KEY_PATH" > "$PUB_PATH"
  chmod 644 "$PUB_PATH"
  ok "key: $KEY_PATH"
  ok "pub: $PUB_PATH"
fi

# ─── 3. add to agent ────────────────────────────
note "ssh-add $KEY_PATH"
ssh-add "$KEY_PATH" 2>&1 | sed 's/^/  /'
ok "key loaded into agent"

# ─── 4. create vault skeleton ───────────────────
VAULT_DIR="$SSH_DIR/vault"
if [ ! -d "$VAULT_DIR" ]; then
  note "creating $VAULT_DIR"
  mkdir -p "$VAULT_DIR"
  if [ ! -f "$VAULT_DIR/hosts.toml" ]; then
    cat > "$VAULT_DIR/hosts.toml" <<'EOF'
# hosts.toml — add your servers here, then run `sshvault push`
# Example:
# [hosts.prod-web]
# user = "deploy"
# host = "10.0.1.10"
# port = 22
# desc = "Frontend production"
# tags = ["prod", "web"]
EOF
  fi
  ok "vault skeleton created"
fi

# ─── 5. print public key so user can copy it ────
echo ""
echo "─────────────────────────────────────────────────────"
echo "Your public key (copy this to the server's authorized_keys):"
echo ""
cat "$PUB_PATH"
echo ""
echo "─────────────────────────────────────────────────────"
echo ""
ok "done. next step:"
echo "  ./scripts/remote/install-key-remote.sh user@host"
