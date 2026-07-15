#!/usr/bin/env bash
# diagnose-remote.sh
# Connect to a server with password and report EVERYTHING that could be wrong
# with public-key auth. Output is grep-friendly.
#
# Usage:
#   ./diagnose-remote.sh umbrel@192.168.18.238
set -euo pipefail

[ $# -ge 1 ] || { sed -n '2,8p' "$0"; exit 1; }
TARGET="$1"

note() { echo "==> $*"; }

# Check if we have sshpass or need to ask the user
PW=""
if command -v sshpass >/dev/null 2>&1; then
  read -s -p "password for $TARGET: " PW; echo
fi

note "1. who am I on the server?"
if [ -n "$PW" ]; then
  sshpass -p "$PW" ssh -o StrictHostKeyChecking=accept-new "$TARGET" 'whoami; id; uname -a'
else
  ssh -o StrictHostKeyChecking=accept-new "$TARGET" 'whoami; id; uname -a'
fi

note "2. where does sshd look for authorized_keys?"
if [ -r /etc/ssh/sshd_config ]; then
  echo "    (we can't read this without root, but we'll check the user's file)"
fi
# Ask the server
if [ -n "$PW" ]; then
  sshpass -p "$PW" ssh "$TARGET" '
    echo "    AuthorizedKeysFile (default if not set):"
    echo "      ~/.ssh/authorized_keys"
    echo "      ~/.ssh/authorized_keys2"
    echo
    echo "    PUBKEY_AUTH setting in /etc/ssh/sshd_config:"
    grep -iE "^(PubkeyAuthentication|PermitRootLogin|PasswordAuthentication|AllowUsers|AllowGroups|AuthorizedKeysFile|AuthorizedKeysCommand|AuthorizedPrincipalsFile|ChallengeResponseAuthentication|UsePAM)" /etc/ssh/sshd_config 2>/dev/null | grep -v "^#" || echo "      (cannot read sshd_config as non-root)"
    echo
    echo "    sshd_config includes:"
    ls /etc/ssh/sshd_config.d/ 2>/dev/null || echo "      (no drop-in dir)"
  '
else
  ssh "$TARGET" '
    grep -iE "^(PubkeyAuthentication|AllowUsers|AllowGroups|AuthorizedKeysFile)" /etc/ssh/sshd_config 2>/dev/null | grep -v "^#" || echo "      (cannot read sshd_config as non-root)"
  '
fi

note "3. the authorized_keys file"
if [ -n "$PW" ]; then
  sshpass -p "$PW" ssh "$TARGET" '
    echo "    path: \$HOME/.ssh/authorized_keys"
    echo "    expanded: \$HOME = $HOME"
    echo "    exists? $(test -f ~/.ssh/authorized_keys && echo yes || echo NO)"
    echo "    perms: $(stat -c "%a %U:%G" ~/.ssh/authorized_keys 2>/dev/null || stat -f "%Lp %Su:%Sg" ~/.ssh/authorized_keys 2>/dev/null)"
    echo "    sshd wants perms <= 600 and dir perms <= 755"
    echo "    line count: $(wc -l < ~/.ssh/authorized_keys 2>/dev/null || echo N/A)"
    echo "    last 3 lines (sanitized):"
    tail -n 3 ~/.ssh/authorized_keys 2>/dev/null | sed "s/^/      /" || echo "      (cannot read)"
    echo
    echo "    ~/.ssh perms: $(stat -c "%a %U:%G" ~/.ssh 2>/dev/null || stat -f "%Lp %Su:%Sg" ~/.ssh 2>/dev/null)"
    echo "    ~ perms:     $(stat -c "%a %U:%G" ~ 2>/dev/null || stat -f "%Lp %Su:%Sg" ~ 2>/dev/null)"
  '
else
  ssh "$TARGET" '
    echo "    exists? $(test -f ~/.ssh/authorized_keys && echo yes || echo NO)"
    echo "    perms: $(stat -c "%a" ~/.ssh/authorized_keys 2>/dev/null)"
    echo "    line count: $(wc -l < ~/.ssh/authorized_keys 2>/dev/null || echo N/A)"
  '
fi

note "4. is our key actually in authorized_keys?"
PUB=$(cat ~/.ssh/id_ed25519.pub 2>/dev/null || echo "")
if [ -n "$PUB" ] && [ -n "$PW" ]; then
  sshpass -p "$PW" ssh "$TARGET" "grep -Fxq '$PUB' ~/.ssh/authorized_keys && echo '    YES, our key is in the file' || echo '    NO, our key is NOT in the file'"
elif [ -n "$PUB" ]; then
  ssh "$TARGET" "grep -Fxq '$PUB' ~/.ssh/authorized_keys && echo '    YES' || echo '    NO'"
fi

note "5. selinux / apparmor (can block sshd from reading the file)"
if [ -n "$PW" ]; then
  sshpass -p "$PW" ssh "$TARGET" '
    if command -v getenforce >/dev/null; then
      echo "    SELinux: $(getenforce 2>/dev/null)"
      echo "    SSH home context (if SELinux):"
      ls -lZ ~/.ssh/authorized_keys 2>/dev/null | awk "{print \$1, \$NF}"
    fi
    if command -v aa-status >/dev/null; then
      echo "    AppArmor: $(aa-status 2>/dev/null | head -2)"
    fi
  '
fi

note "6. recent auth log lines for our user"
if [ -n "$PW" ]; then
  sshpass -p "$PW" ssh "$TARGET" '
    for f in /var/log/auth.log /var/log/secure /var/log/audit/audit.log; do
      if [ -r "$f" ]; then
        echo "    tail of $f:"
        tail -n 20 "$f" 2>/dev/null | grep -iE "(sshd|authentication|fail|publickey)" | tail -10 | sed "s/^/      /"
        break
      fi
    done
  '
fi

note "7. what sshd is actually doing (verbose client log)"
ssh -vvv -o BatchMode=yes -o PasswordAuthentication=no "$TARGET" true 2>&1 | \
  grep -E "debug[0-9]: (Authentications|Server accepts|Trying private|sign|userauth)" | \
  sed 's/^/    /' || true

echo
echo "==> done. paste this output back if you need help."
