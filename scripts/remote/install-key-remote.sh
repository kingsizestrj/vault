#!/usr/bin/env bash
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# install-key-remote.sh  (Linux / macOS)
# Instala a chave pública no servidor remoto.
#
# Uso:
#   ./install-key-remote.sh user@host
#   ./install-key-remote.sh user@host --port 2222
#   ./install-key-remote.sh user@host --key ~/.ssh/work_key.pub
#
# Se o server ainda não tem sua chave, vai pedir senha.
# Roda 1 vez por server, depois nunca mais.
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
set -euo pipefail

[ $# -ge 1 ] || { sed -n '2,12p' "$0"; exit 1; }

TARGET="$1"; shift
PORT=""
PUB_KEY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) PORT="$2"; shift 2 ;;
    --key)  PUB_KEY="$2"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

note() { echo "→ $*"; }
ok()   { echo "✓ $*"; }
die()  { echo "✗ $*" >&2; exit 1; }

# pick pub key if not given
if [ -z "$PUB_KEY" ]; then
  for c in "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_rsa.pub" "$HOME/.ssh/id_ecdsa.pub"; do
    if [ -f "$c" ]; then PUB_KEY="$c"; break; fi
  done
fi
[ -n "$PUB_KEY" ] && [ -f "$PUB_KEY" ] || die "no public key found (use --key)"
note "public key: $PUB_KEY"

# build ssh opts
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)
[ -n "$PORT" ] && SSH_OPTS+=(-p "$PORT")

# 1. check if we can already log in keylessly (already installed?)
note "checking existing key auth to $TARGET"
if ssh "${SSH_OPTS[@]}" -o BatchMode=yes -o PasswordAuthentication=no "$TARGET" true 2>/dev/null; then
  ok "key already installed on $TARGET — nothing to do"
  exit 0
fi

# 2. try ssh-copy-id first (asks for password once)
note "running ssh-copy-id (will prompt for password ONCE)"
if command -v ssh-copy-id >/dev/null 2>&1; then
  if [ -n "$PORT" ]; then
    ssh-copy-id "${SSH_OPTS[@]}" -p "$PORT" -i "$PUB_KEY" "$TARGET"
  else
    ssh-copy-id "${SSH_OPTS[@]}" -i "$PUB_KEY" "$TARGET"
  fi
else
  # 3. fallback: manual copy
  note "ssh-copy-id not found, doing it manually"
  PUB_CONTENT=$(cat "$PUB_KEY")
  ssh "${SSH_OPTS[@]}" "$TARGET" "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$PUB_CONTENT' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && echo OK"
fi

# 4. verify
note "verifying key auth"
if ssh "${SSH_OPTS[@]}" -o BatchMode=yes "$TARGET" true 2>/dev/null; then
  ok "key installed on $TARGET — next time: ssh $TARGET"
else
  die "key install seemed to fail — check ~/.ssh/authorized_keys on $TARGET"
fi
