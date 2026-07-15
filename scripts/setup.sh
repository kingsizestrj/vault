#!/usr/bin/env bash
# setup.sh  (Linux / macOS)
# One-shot setup wizard. Run on a fresh machine and answer the prompts.
#
# What it does:
#   1. Asks for the Gitea repo URL, clones it to ~/.ssh/vault
#   2. Installs sshvault in /usr/local/bin
#   3. Sets up the local SSH key (generate new OR restore from backup)
#   4. Guides you through installing the public key on remote servers
#   5. Adds hosts to the vault
#   6. Pushes everything to Gitea
#
# Usage:
#   ./scripts/setup.sh
set -euo pipefail

SSH_DIR="$HOME/.ssh"
VAULT="$SSH_DIR/vault"

# Termux (Android) has no /usr/local/bin and no root/sudo; it installs into
# $PREFIX/bin (already on PATH). Detect it and pick the right install dir.
IS_TERMUX=0
case "${PREFIX:-}" in *com.termux*) IS_TERMUX=1 ;; esac
[ -n "${TERMUX_VERSION:-}" ] && IS_TERMUX=1
if [ "$IS_TERMUX" = "1" ]; then
  BINDIR="${PREFIX}/bin"
else
  BINDIR="/usr/local/bin"
fi

# -- colors / helpers -------------------------------------
if [ -t 1 ] && command -v tput >/dev/null 2>&1; then
  C_CYAN="\033[36m"; C_GREEN="\033[32m"; C_YELLOW="\033[33m"; C_RED="\033[31m"; C_MAGENTA="\033[35m"; C_GRAY="\033[90m"; C_RST="\033[0m"
else
  C_CYAN=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_MAGENTA=""; C_GRAY=""; C_RST=""
fi

banner() {
  printf "\n"
  printf "${C_MAGENTA}  +----------------------------------------------+${C_RST}\n"
  printf "${C_MAGENTA}  |  sshvault setup wizard                        |${C_RST}\n"
  printf "${C_GRAY}  |  Gitea-synced SSH host manager                |${C_RST}\n"
  printf "${C_MAGENTA}  +----------------------------------------------+${C_RST}\n"
  printf "\n"
}
step()   { printf "\n${C_CYAN}-- step %s : %s --${C_RST}\n\n" "$1" "$2"; }
note()   { printf "  ${C_CYAN}-> %s${C_RST}\n" "$*"; }
ok()     { printf "  ${C_GREEN}[OK] %s${C_RST}\n" "$*"; }
warn()   { printf "  ${C_YELLOW}[!] %s${C_RST}\n" "$*"; }
die()    { printf "  ${C_RED}[X] %s${C_RST}\n" "$*" >&2; exit 1; }
ask() {
  local q="$1" def="${2:-}"
  if [ -n "$def" ]; then
    printf "  ${C_YELLOW}? %s [%s]: ${C_RST}" "$q" "$def"
  else
    printf "  ${C_YELLOW}? %s: ${C_RST}" "$q"
  fi
  read -r ans
  if [ -z "$ans" ]; then echo "$def"; else echo "$ans"; fi
}
ask_yn() {
  local q="$1" def="${2:-y}"
  local yn="y/N"; [ "$def" = "y" ] && yn="Y/n"
  printf "  ${C_YELLOW}? %s [%s]: ${C_RST}" "$q" "$yn"
  read -r ans
  ans="${ans:-$def}"
  case "$ans" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac

}
ask_secret() {
  local q="$1"
  printf "  ${C_YELLOW}? %s: ${C_RST}" "$q"
  local ans
  if [ -t 0 ]; then
    read -rs ans
    echo
  else
    read -r ans
  fi
  echo "$ans"
}

banner

# -- step 1 : git + repo URL -----------------------------
step 1 "git + repo"
command -v git >/dev/null 2>&1 || die "git not found - install it first"
ok "git found: $(command -v git)"

if [ -d "$VAULT" ]; then
  warn "$VAULT already exists"
  if ! ask_yn "reuse it?"; then die "move it away and run setup again"; fi
else
  REPO=$(ask "Gitea repo URL (e.g. git@git.seudominio.com:user/vault.git)")
  [ -n "$REPO" ] || die "repo URL required"
  mkdir -p "$SSH_DIR"; chmod 700 "$SSH_DIR"
  note "cloning $REPO -> $VAULT"
  git clone "$REPO" "$VAULT"
fi

cd "$VAULT"
ok "in $(pwd)"

# -- step 2 : install sshvault binary --------------------
step 2 "install sshvault binary"
# pick a usable binary for this OS/arch. The repo ships the canonical
# `sshvault` (Linux x86_64); per-arch names and macOS builds are optional.
OS="$(uname -s)"
case "$(uname -m)" in
  x86_64|amd64)   GOARCH=amd64 ;;
  aarch64|arm64)  GOARCH=arm64 ;;
  *)              GOARCH="" ;;
esac

BIN=""
case "$OS" in
  Linux)
    CANDIDATES="sshvault-linux-$GOARCH"
    [ "$GOARCH" = "amd64" ] && CANDIDATES="$CANDIDATES sshvault"
    ;;
  Darwin)
    CANDIDATES="sshvault-darwin-$GOARCH sshvault-darwin-arm64 sshvault-darwin-amd64"
    ;;
  *)
    die "unsupported OS: $OS"
    ;;
esac
for c in $CANDIDATES; do
  if [ -f "$c" ]; then BIN="$c"; break; fi
done

# No prebuilt binary for this OS/arch? Build one from source if we can.
if [ -z "$BIN" ] && [ -f "main.go" ] && command -v go >/dev/null 2>&1; then
  note "no prebuilt binary for $OS/$GOARCH — building from source (go build)"
  if go build -ldflags "-s -w" -o sshvault-built . ; then
    BIN="sshvault-built"; ok "built $BIN"
  else
    warn "go build failed"
  fi
fi

TARGET="$BINDIR/sshvault"
if [ -f "$BIN" ]; then
  if [ -w "$BINDIR" ]; then
    note "installing $BIN -> $TARGET"
    cp "$BIN" "$TARGET"
    chmod +x "$TARGET"
    ok "installed: $TARGET"
  elif command -v sudo >/dev/null 2>&1; then
    note "installing $BIN -> $TARGET (via sudo)"
    sudo cp "$BIN" "$TARGET"
    sudo chmod +x "$TARGET"
    ok "installed: $TARGET"
  else
    warn "no write access to $BINDIR and no sudo; leaving binary in repo"
    TARGET="$VAULT/sshvault"
    cp "$BIN" "$TARGET"
    chmod +x "$TARGET"
    note "add $VAULT to your PATH, or call $TARGET directly"
  fi
else
  warn "$BIN not found in repo - run from source (go build .) or download a release"
fi

if command -v sshvault >/dev/null 2>&1; then
  ok "sshvault callable: $(command -v sshvault)"
else
  warn "sshvault not yet in PATH for this shell"
fi

# -- step 3 : local SSH key -------------------------------
step 3 "local SSH key"
KEY="$SSH_DIR/id_ed25519"
PUB="$SSH_DIR/id_ed25519.pub"

if [ -f "$KEY" ]; then
  ok "key already exists at $KEY (skipping generation)"
else
  echo
  echo "  Choose how to set up your private key:"
  echo -e "    ${C_GRAY}1) Generate a new ed25519 key (no passphrase, recommended)${C_RST}"
  echo -e "    ${C_GRAY}2) Generate a new ed25519 key WITH a passphrase${C_RST}"
  echo -e "    ${C_GRAY}3) Restore from a backup file${C_RST}"
  CHOICE=$(ask "choice" "1")
  CHOICE="${CHOICE:-1}"
  case "$CHOICE" in
    3)
      BACKUP=$(ask "path to backup key (e.g. /mnt/usb/id_ed25519)")
      [ -f "$BACKUP" ] || die "not found: $BACKUP"
      note "installing $BACKUP -> $KEY"
      cp "$BACKUP" "$KEY"
      chmod 600 "$KEY"
      [ -f "$PUB" ] || ssh-keygen -y -f "$KEY" > "$PUB"
      ;;
    2)
      note "generating key (you will be asked for a passphrase)"
      ssh-keygen -t ed25519 -f "$KEY"
      ;;
    *)
      note "generating key with no passphrase"
      ssh-keygen -t ed25519 -f "$KEY" -N ""
      ;;
  esac
  chmod 700 "$SSH_DIR"
  chmod 644 "$PUB"
  ok "private: $KEY"
  ok "public:  $PUB"
fi

# ensure ssh-agent is running and key is loaded.
# Use the numeric uid (id -u), not $USER, which Termux often leaves unset.
if ! pgrep -u "$(id -u)" ssh-agent >/dev/null 2>&1; then
  note "starting ssh-agent"
  ssh-agent -s | head -2 > "$SSH_DIR/agent.env"
fi
# shellcheck disable=SC1091
. "$SSH_DIR/agent.env" 2>/dev/null || true
ssh-add "$KEY" 2>&1 | sed 's/^/    /'
ok "key loaded into ssh-agent"

# -- step 4 : install public key on remote server(s) ------
step 4 "install public key on remote server(s)"
echo
echo "  For each server, you'll be asked for:"
echo "    - user@host (e.g. deploy@10.0.1.10)"
echo "    - port (default 22)"
echo "  The script will prompt for the server's password ONCE,"
echo "  install the public key, and verify it works."
echo

while :; do
  TARGET_HOST=$(ask "user@host to set up (blank to skip / finish)")
  [ -n "$TARGET_HOST" ] || break
  PORT_ARG=""
  PORT=$(ask "port" "22")
  [ -n "$PORT" ] && [ "$PORT" != "22" ] && PORT_ARG="--port $PORT"
  # host MUST come first: install-key-remote.sh reads $1 as the target,
  # then parses flags. Passing --port before it aborts the sub-script.
  bash "$VAULT/scripts/remote/install-key-remote.sh" "$TARGET_HOST" $PORT_ARG || \
    warn "install on $TARGET_HOST returned non-zero - fix it and re-run setup later"
  ask_yn "set up another server?" || break
done

# -- step 5 : add hosts to vault --------------------------
step 5 "add hosts to the vault"
echo
echo "  Now let's add hosts. For each one, answer the prompts."
echo "  (Leave 'alias' blank to stop.)"
echo

HOSTS_FILE="$VAULT/hosts.toml"
[ -f "$HOSTS_FILE" ] || : > "$HOSTS_FILE"

while :; do
  echo
  note "adding a host (leave alias blank to finish)"
  ALIAS=$(ask "alias (e.g. prod-web)")
  [ -n "$ALIAS" ] || break
  USER_=$(ask "ssh user" "root")
  HOST_=$(ask "hostname or IP (e.g. 10.0.1.10)")
  [ -n "$HOST_" ] || { warn "hostname required, skipping"; continue; }
  PORT=$(ask "port" "22")
  DESC=$(ask "description")
  TAGS=$(ask "tags (comma separated, e.g. prod,web,critical)")

  # validate the alias as a bare TOML key (avoids needing to quote the table
  # header, and keeps aliases usable on the command line)
  case "$ALIAS" in
    *[!A-Za-z0-9_-]*|"") warn "alias must be [A-Za-z0-9_-]; skipping '$ALIAS'"; continue ;;
  esac
  # validate the port; fall back to 22 on empty/non-numeric input
  case "${PORT:-22}" in
    *[!0-9]*|"") PORT=22 ;;
  esac

  # escape backslashes and double quotes for TOML string values so that
  # user input can never break out of the quoted string (and never gets
  # interpreted as a printf format).
  esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

  {
    printf '\n[hosts.%s]\n' "$ALIAS"
    printf 'user = "%s"\n' "$(esc "$USER_")"
    printf 'host = "%s"\n' "$(esc "$HOST_")"
    printf 'port = %s\n' "$PORT"
    [ -n "$DESC" ] && printf 'desc = "%s"\n' "$(esc "$DESC")"
    if [ -n "$TAGS" ]; then
      TAGS_TOML=""
      OLD_IFS=$IFS; IFS=','
      for t in $TAGS; do
        t=$(printf '%s' "$t" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [ -n "$t" ] || continue
        TAGS_TOML="${TAGS_TOML}\"$(esc "$t")\", "
      done
      IFS=$OLD_IFS
      TAGS_TOML=${TAGS_TOML%, }
      [ -n "$TAGS_TOML" ] && printf 'tags = [%s]\n' "$TAGS_TOML"
    fi
  } >> "$HOSTS_FILE"
  ok "added: $ALIAS"
done

# -- step 6 : commit + push -------------------------------
step 6 "sync to Gitea"
if [ -z "$(git status --porcelain)" ]; then
  note "no changes to commit"
else
  MSG=$(ask "commit message" "update vault")
  git add -A
  git commit -q -m "$MSG"
  ok "committed"
  note "pushing to Gitea..."
  if git push; then
    ok "pushed"
  else
    warn "git push failed - run 'sshvault push' later to retry"
  fi
fi

# -- done -------------------------------------------------
step "done!"
printf "  ${C_GREEN}Everything is set up. Try:${C_RST}\n\n"
printf "    sshvault             ${C_GRAY}# open the TUI${C_RST}\n"
printf "    sshvault list        ${C_GRAY}# see all hosts${C_RST}\n"
printf "    sshvault <alias>     ${C_GRAY}# connect directly${C_RST}\n"
printf "\n  ${C_CYAN}On other machines, just run this setup.sh again with the same repo.${C_RST}\n"
printf "\n"
