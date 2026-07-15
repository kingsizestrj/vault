#!/usr/bin/env bash
# diagnose-remote.sh
# Connect to a server and report EVERYTHING that could be wrong with
# public-key auth. Output is grep-friendly.
#
# Usage:
#   ./diagnose-remote.sh user@host
#   ./diagnose-remote.sh user@host -p 2222     # (extra ssh opts after the host)
#
# The password (if needed) is asked at most ONCE: all checks reuse a single
# multiplexed ssh connection. The password is never placed on a command line.
set -uo pipefail

[ $# -ge 1 ] || { sed -n '2,9p' "$0"; exit 1; }
TARGET="$1"; shift
EXTRA_OPTS=("$@")   # any extra ssh options (e.g. -p 2222)

note() { echo "==> $*"; }

# One multiplexed connection, reused by every check. ControlPersist keeps it
# alive briefly so we authenticate once. %r/%h/%p are per-target so parallel
# runs don't collide.
CTL="${TMPDIR:-/tmp}/sshvault-diag-$$-%r@%h-%p"
SSH_OPTS=(-o "ControlMaster=auto" -o "ControlPath=$CTL" -o "ControlPersist=120"
          -o "StrictHostKeyChecking=accept-new" -o "ConnectTimeout=10" "${EXTRA_OPTS[@]}")

cleanup() { ssh -o "ControlPath=$CTL" -O exit "$TARGET" 2>/dev/null || true; }
trap cleanup EXIT

# --- open the master connection (the only password prompt) ---------------
note "opening connection to $TARGET"
if command -v sshpass >/dev/null 2>&1; then
  read -rsp "password for $TARGET (blank = use key/agent): " PW; echo
  if [ -n "$PW" ]; then
    # sshpass -e reads the password from the SSHPASS env var, so it never
    # appears in the process list (unlike sshpass -p "$PW").
    SSHPASS="$PW" sshpass -e ssh "${SSH_OPTS[@]}" "$TARGET" true \
      || { note "could not open connection"; exit 1; }
    unset PW SSHPASS
  else
    ssh "${SSH_OPTS[@]}" "$TARGET" true || { note "could not open connection"; exit 1; }
  fi
else
  note "sshpass not installed — you'll be asked for the password ONCE (connection is reused)"
  ssh "${SSH_OPTS[@]}" "$TARGET" true || { note "could not open connection"; exit 1; }
fi

# Every subsequent call reuses the master: no password, no re-prompt.
rssh() { ssh "${SSH_OPTS[@]}" "$TARGET" "$@"; }

note "1. who am I on the server?"
rssh 'whoami; id; uname -a'

note "2. sshd auth settings (may be unreadable without root)"
rssh '
  echo "    default AuthorizedKeysFile: ~/.ssh/authorized_keys, ~/.ssh/authorized_keys2"
  echo "    sshd_config (non-comment auth lines):"
  grep -iE "^(PubkeyAuthentication|PermitRootLogin|PasswordAuthentication|AllowUsers|AllowGroups|AuthorizedKeysFile|AuthorizedKeysCommand|AuthorizedPrincipalsFile|ChallengeResponseAuthentication|UsePAM)" /etc/ssh/sshd_config 2>/dev/null | grep -v "^#" || echo "      (cannot read sshd_config as non-root)"
  echo "    drop-in dir /etc/ssh/sshd_config.d/:"
  ls /etc/ssh/sshd_config.d/ 2>/dev/null | sed "s/^/      /" || echo "      (none)"
'

note "3. the authorized_keys file + home/dir perms"
rssh '
  echo "    exists?  $(test -f ~/.ssh/authorized_keys && echo yes || echo NO)"
  echo "    ak perms: $(stat -c "%a %U:%G" ~/.ssh/authorized_keys 2>/dev/null || stat -f "%Lp %Su:%Sg" ~/.ssh/authorized_keys 2>/dev/null)"
  echo "    ak lines: $(wc -l < ~/.ssh/authorized_keys 2>/dev/null || echo N/A)"
  echo "    ~/.ssh:  $(stat -c "%a %U:%G" ~/.ssh 2>/dev/null || stat -f "%Lp %Su:%Sg" ~/.ssh 2>/dev/null)"
  echo "    ~ home:  $(stat -c "%a %U:%G" ~ 2>/dev/null || stat -f "%Lp %Su:%Sg" ~ 2>/dev/null)"
  echo "    (sshd wants authorized_keys <= 600 and ~/.ssh <= 700, home not group/other-writable)"
'

note "4. is our public key already in authorized_keys?"
PUB=$(cat ~/.ssh/id_ed25519.pub 2>/dev/null || true)
if [ -n "$PUB" ]; then
  rssh "grep -Fq '$PUB' ~/.ssh/authorized_keys 2>/dev/null && echo '    YES, our key is present' || echo '    NO, our key is NOT present'"
else
  echo "    (no local ~/.ssh/id_ed25519.pub to compare)"
fi

note "5. SELinux / AppArmor (can block sshd from reading the file)"
rssh '
  if command -v getenforce >/dev/null 2>&1; then
    echo "    SELinux: $(getenforce 2>/dev/null)"
    ls -lZ ~/.ssh/authorized_keys 2>/dev/null | awk "{print \$1, \$NF}" | sed "s/^/      /"
  fi
  if command -v aa-status >/dev/null 2>&1; then
    echo "    AppArmor: $(aa-status 2>/dev/null | head -1)"
  fi
  command -v getenforce >/dev/null 2>&1 || command -v aa-status >/dev/null 2>&1 || echo "    (no SELinux/AppArmor tooling found)"
'

note "6. recent auth-log lines"
rssh '
  for f in /var/log/auth.log /var/log/secure /var/log/audit/audit.log; do
    if [ -r "$f" ]; then
      echo "    tail of $f:"
      tail -n 40 "$f" 2>/dev/null | grep -iE "(sshd|authentication|fail|publickey)" | tail -10 | sed "s/^/      /"
      break
    fi
  done
'

note "7. verbose client handshake (local ssh -vvv, key-only)"
ssh -vvv -o BatchMode=yes -o PasswordAuthentication=no "${EXTRA_OPTS[@]}" "$TARGET" true 2>&1 | \
  grep -E "debug[0-9]: (Authentications|Server accepts|Trying private|sign|userauth)" | \
  sed 's/^/    /' || true

echo
echo "==> done. paste this output back if you need help."
