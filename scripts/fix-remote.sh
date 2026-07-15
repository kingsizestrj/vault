#!/usr/bin/env bash
# fix-remote.sh — to be PASTED INSIDE the server (after ssh umbrel@host)
# Repairs the most common authorized_keys problems non-interactively.
#
# Usage: paste this whole file into the server terminal after
#        `ssh umbrel@192.168.18.238` (using the password, not the key)
set -euo pipefail

echo "==> current state of ~/.ssh"
if ! ls -la ~/.ssh 2>/dev/null; then
  mkdir -p ~/.ssh && chmod 700 ~/.ssh && ls -la ~/.ssh
fi
echo

echo "==> permissions on authorized_keys (if it exists)"
if [ -f ~/.ssh/authorized_keys ]; then
  stat -c "    mode=%a owner=%U:%G size=%s" ~/.ssh/authorized_keys 2>/dev/null \
    || stat -f "    mode=%Lp owner=%Su:%Sg size=%z" ~/.ssh/authorized_keys
  echo "    line count: $(wc -l < ~/.ssh/authorized_keys)"
  echo "    last 2 lines (sanitized):"
  tail -n 2 ~/.ssh/authorized_keys | awk '{print "      "substr($0,1,40)"..."}'
else
  echo "    (file does not exist)"
fi
echo

echo "==> applying fix: enforce strict perms"
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys 2>/dev/null || {
  echo "    (authorized_keys didn't exist, creating empty)"
  : > ~/.ssh/authorized_keys
  chmod 600 ~/.ssh/authorized_keys
}
chmod 755 ~ 2>/dev/null || chmod 750 ~
echo "    done"
echo

echo "==> final state"
akcount=$(wc -l < ~/.ssh/authorized_keys 2>/dev/null || echo 0)
# GNU coreutils uses `stat -c`; macOS/BSD uses `stat -f`. Try both.
stat -c "    ~ = mode %a (%U:%G)" ~ 2>/dev/null \
  || stat -f "    ~ = mode %Lp (%Su:%Sg)" ~ 2>/dev/null
stat -c "    ~/.ssh = mode %a (%U:%G)" ~/.ssh 2>/dev/null \
  || stat -f "    ~/.ssh = mode %Lp (%Su:%Sg)" ~/.ssh 2>/dev/null
stat -c "    ~/.ssh/authorized_keys = mode %a (%U:%G), $akcount keys" ~/.ssh/authorized_keys 2>/dev/null \
  || stat -f "    ~/.ssh/authorized_keys = mode %Lp (%Su:%Sg), $akcount keys" ~/.ssh/authorized_keys 2>/dev/null
echo
echo "==> now retry from your machine:"
echo "    ssh umbrel@192.168.18.238"
