#!/usr/bin/env bash
set -euo pipefail

THRESHOLD="${SSH_FAIL_THRESHOLD:-5}"
SINCE_WINDOW="${SSH_SINCE_WINDOW:-24 hours ago}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Erreur : ce script doit etre lance en root." >&2
  exit 1
fi

logs="$(journalctl -u ssh -u sshd --since "${SINCE_WINDOW}" --no-pager 2>/dev/null || true)"
total_failed="$(printf '%s\n' "${logs}" | grep -Ec 'Failed (password|publickey) for|Invalid user' || true)"
total_success="$(printf '%s\n' "${logs}" | grep -Ec 'Accepted (publickey|password) for' || true)"

echo "Connexions reussies : ${total_success}"
echo "Tentatives echouees : ${total_failed}"
echo "--- Echecs par IP ---"
printf '%s\n' "${logs}" | grep -E 'Failed (password|publickey) for|Invalid user' | grep -oE 'from ([0-9]{1,3}\.){3}[0-9]{1,3}|from [0-9a-fA-F:]+' | awk '{print $2}' | sort | uniq -c | sort -nr || true
echo "--- Comptes vises ---"
printf '%s\n' "${logs}" | sed -nE 's/.*Failed (password|publickey) for (invalid user )?([^ ]+).*/\3/p; s/.*Invalid user ([^ ]+).*/\1/p' | sort | uniq -c | sort -nr || true

if (( total_failed > THRESHOLD )); then
  exit 2
fi
exit 0
