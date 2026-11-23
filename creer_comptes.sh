#!/usr/bin/env bash
set -euo pipefail

CSV_FILE="${1:-./comptes.csv}"
KEYS_DIR="${2:-./config/authorized_keys}"
FREELANCE_EXPIRY="${FREELANCE_EXPIRY:-2026-12-31}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Erreur : ce script doit etre lance en root." >&2
  exit 1
fi

for g in admins support acces_ssh dev design commercial freelance; do
  getent group "${g}" >/dev/null 2>&1 || groupadd "${g}"
done

while IFS= read -r line || [[ -n "${line}" ]]; do
  line="${line//$'\r'/}"
  [[ -z "${line}" || "${line}" == login\;* ]] && continue
  IFS=';' read -r login nom grp_pri grp_sec _ <<< "${line}"
  login="${login// /}"
  grp_pri="${grp_pri// /}"
  grp_sec="${grp_sec// /}"
  [[ -z "${login}" || -z "${grp_pri}" ]] && continue

  getent group "${grp_pri}" >/dev/null 2>&1 || groupadd "${grp_pri}"

  if ! id "${login}" >/dev/null 2>&1; then
    if [[ "${grp_pri}" == "freelance" ]]; then
      useradd -m -s /bin/bash -g "${grp_pri}" -e "${FREELANCE_EXPIRY}" -c "${nom}" "${login}"
    else
      useradd -m -s /bin/bash -g "${grp_pri}" -c "${nom}" "${login}"
    fi
  else
    usermod -g "${grp_pri}" -c "${nom}" "${login}"
    if [[ "${grp_pri}" == "freelance" ]]; then
      chage -E "${FREELANCE_EXPIRY}" "${login}"
    fi
  fi

  if [[ -n "${grp_sec}" ]]; then
    IFS=',' read -ra sec_arr <<< "${grp_sec}"
    for sg in "${sec_arr[@]}"; do
      sg="${sg// /}"
      [[ -z "${sg}" ]] && continue
      getent group "${sg}" >/dev/null 2>&1 || groupadd "${sg}"
      usermod -aG "${sg}" "${login}"
    done
  fi

  chmod 700 "/home/${login}" 2>/dev/null || true

  key_file="${KEYS_DIR}/${login}.pub"
  home_dir="$(getent passwd "${login}" | cut -d: -f6)"
  if [[ -n "${home_dir}" && -f "${key_file}" ]]; then
    install -d -m 700 -o "${login}" -g "${grp_pri}" "${home_dir}/.ssh"
    install -m 600 -o "${login}" -g "${grp_pri}" "${key_file}" "${home_dir}/.ssh/authorized_keys"
  fi
done < "${CSV_FILE}"

mkdir -p /srv/projets/externe /srv/maquettes /srv/clients
chown -R root:root /srv
chmod 755 /srv

chmod 750 /srv/projets
setfacl -b /srv/projets
setfacl -m u::rwx,g::r-x,o::---,g:dev:rwx,g:design:r-x,g:commercial:---,g:freelance:--x /srv/projets
setfacl -d -m u::rwx,g::r-x,o::---,g:dev:rwx,g:design:r-x,g:commercial:---,g:freelance:--x /srv/projets

chmod 750 /srv/projets/externe
setfacl -b /srv/projets/externe
setfacl -m u::rwx,g::r-x,o::---,g:dev:rwx,g:design:r-x,g:commercial:---,g:freelance:rwx /srv/projets/externe
setfacl -d -m u::rwx,g::r-x,o::---,g:dev:rwx,g:design:r-x,g:commercial:---,g:freelance:rwx /srv/projets/externe

chmod 750 /srv/maquettes
setfacl -b /srv/maquettes
setfacl -m u::rwx,g::r-x,o::---,g:dev:r-x,g:design:rwx,g:commercial:r-x,g:freelance:--x /srv/maquettes
setfacl -d -m u::rwx,g::r-x,o::---,g:dev:r-x,g:design:rwx,g:commercial:r-x,g:freelance:--x /srv/maquettes

chmod 750 /srv/clients
setfacl -b /srv/clients
setfacl -m u::rwx,g::r-x,o::---,g:dev:---,g:design:---,g:commercial:rwx,g:freelance:--x /srv/clients
setfacl -d -m u::rwx,g::r-x,o::---,g:dev:---,g:design:---,g:commercial:rwx,g:freelance:--x /srv/clients
