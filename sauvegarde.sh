#!/usr/bin/env bash
set -euo pipefail

BACKUP_ROOT="${BACKUP_ROOT:-/mnt/backup}"
KEEP_COUNT="${KEEP_COUNT:-7}"
LOG_FILE="${BACKUP_LOG:-/var/log/sauvegarde_pixelia.log}"
SOURCES=(/etc /srv)

if [[ "${EUID}" -ne 0 ]]; then
  echo "Erreur : ce script doit etre lance en root." >&2
  exit 1
fi

mkdir -p "${BACKUP_ROOT}/snapshots"
chown -R root:admins "${BACKUP_ROOT}"
chmod 750 "${BACKUP_ROOT}" "${BACKUP_ROOT}/snapshots"

stamp="$(date +%Y-%m-%d_%H-%M-%S)"
dest="${BACKUP_ROOT}/snapshots/${stamp}"
prev="$(ls -1dt "${BACKUP_ROOT}/snapshots"/20* 2>/dev/null | head -n 1 || true)"

mkdir -p "${dest}"
if [[ -n "${prev}" && -d "${prev}" ]]; then
  rsync -aAX --delete --link-dest="${prev}" "${SOURCES[@]}" "${dest}/"
else
  rsync -aAX --delete "${SOURCES[@]}" "${dest}/"
fi

chown -R root:admins "${dest}"
chmod -R o-rwx "${dest}"
echo "[$(date -Iseconds)] Sauvegarde effectuee : ${dest}" >> "${LOG_FILE}"

old="$(ls -1dt "${BACKUP_ROOT}/snapshots"/20* 2>/dev/null | tail -n +$((KEEP_COUNT + 1)) || true)"
for dir in ${old}; do
  if [[ -d "${dir}" ]]; then
    rm -rf "${dir}"
    echo "[$(date -Iseconds)] Rotation suppression : ${dir}" >> "${LOG_FILE}"
  fi
done
