#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASS=0
TOTAL=0

ok() { PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); printf '[OK] %s %s\n' "$1" "$2"; }
ko() { TOTAL=$((TOTAL + 1)); printf '[KO] %s %s\n' "$1" "$2"; }

miss=0
while IFS= read -r line; do
  [[ -z "${line}" || "${line}" == login\;* ]] && continue
  login="$(printf '%s' "${line}" | cut -d';' -f1)"
  id "${login}" >/dev/null 2>&1 || miss=$((miss + 1))
done < "${SCRIPT_DIR}/comptes.csv"
(( miss == 0 )) && ok "C1" "comptes presents" || ko "C1" "${miss} compte(s) manquant(s)"

exp="$(chage -l ffreelance1 2>/dev/null | awk -F': ' '/Account expires/ {print $2}')"
[[ -n "${exp}" && "${exp}" != "never" ]] && ok "C1" "expiration freelance (${exp})" || ko "C1" "pas d'expiration freelance"

sudo -u ldev1 test -w /srv/projets && ok "C2" "dev ecriture /srv/projets" || ko "C2" "dev /srv/projets"
sudo -u ldesign1 test -r /srv/projets && ! sudo -u ldesign1 test -w /srv/projets && ok "C2" "design lecture /srv/projets" || ko "C2" "design /srv/projets"
! sudo -u ccomm1 test -r /srv/projets && ok "C2" "commercial interdit /srv/projets" || ko "C2" "commercial /srv/projets"
sudo -u ffreelance1 test -w /srv/projets/externe && ok "C2" "freelance ecriture /srv/projets/externe" || ko "C2" "freelance /srv/projets/externe"
sudo -u ldesign1 test -w /srv/maquettes && sudo -u ccomm1 test -r /srv/maquettes && ok "C2" "droits /srv/maquettes" || ko "C2" "/srv/maquettes"
sudo -u ccomm1 test -w /srv/clients && ! sudo -u ldev1 test -r /srv/clients && ok "C2" "droits /srv/clients" || ko "C2" "/srv/clients"

tmpf="/srv/projets/.test_acl_$$"
sudo -u ldev1 touch "${tmpf}" 2>/dev/null || true
if [[ -f "${tmpf}" ]] && sudo -u ldesign1 test -r "${tmpf}" && ! sudo -u ccomm1 test -r "${tmpf}"; then
  rm -f "${tmpf}" && ok "C2" "ACL par defaut actives"
else
  rm -f "${tmpf}" && ko "C2" "ACL par defaut inactives"
fi

rules="$(sudo -l -U support 2>/dev/null || true)"
if printf '%s' "${rules}" | grep -q '/usr/local/sbin/analyse_logs.sh' && ! printf '%s' "${rules}" | grep -q '(ALL'; then
  ok "C3" "sudo support limite a analyse_logs.sh"
else
  ko "C3" "sudo support invalide"
fi

if sudo -l -U ffreelance1 2>&1 | grep -qiE 'not allowed|aucun|ne peut pas'; then
  ok "C3" "freelance sans sudo"
else
  ko "C3" "freelance a sudo"
fi

[[ "$(passwd -S root | awk '{print $2}')" == "L" ]] && ok "C4" "root verrouille" || ko "C4" "root non verrouille"
[[ "$(stat -c '%a' /home/ldev1)" == "700" ]] && ok "C4" "home en 700" || ko "C4" "home pas en 700"

sshd -T | grep -qi '^passwordauthentication no$' && ok "S1" "pas de mot de passe SSH" || ko "S1" "PasswordAuthentication"
sshd -T | grep -qi '^permitrootlogin no$' && ok "S2" "root SSH interdit" || ko "S2" "PermitRootLogin"
sshd -T | grep -qi '^allowgroups acces_ssh$' && ok "S3" "AllowGroups acces_ssh" || ko "S3" "AllowGroups"

tries="$(sshd -T | awk '/^maxauthtries / {print $2}')"
alive="$(sshd -T | awk '/^clientaliveinterval / {print $2}')"
(( tries <= 4 && alive > 0 && alive <= 900 )) && ok "S4" "limites SSH (${tries}/${alive}s)" || ko "S4" "limites SSH"

sshd -t 2>/dev/null && [[ -f /etc/ssh/sshd_config.d/99-hardening.conf ]] && ok "S5" "sshd_config.d valide" || ko "S5" "sshd_config.d"

systemctl is-active --quiet fail2ban && fail2ban-client status sshd >/dev/null 2>&1 && ok "J1" "fail2ban actif" || ko "J1" "fail2ban"
nft list chain inet filter input 2>/dev/null | grep -q 'policy drop' && ok "J2" "nftables policy drop" || ko "J2" "nftables"
[[ -d /var/log/journal ]] && ok "J3" "journald persistant" || ko "J3" "journald"
[[ -x /usr/local/sbin/analyse_logs.sh && "$(stat -c '%U:%a' /usr/local/sbin/analyse_logs.sh)" == "root:750" ]] && ok "J4" "analyse_logs.sh ok" || ko "J4" "analyse_logs.sh"

snap_cnt="$(ls -1d /mnt/backup/snapshots/20* 2>/dev/null | wc -l)"
if [[ -x /usr/local/sbin/sauvegarde.sh && -f /etc/cron.d/pixelia-backup && "$(stat -c '%a' /mnt/backup)" == "750" && "${snap_cnt}" -ge 1 ]]; then
  ok "B1-B3" "sauvegarde ok"
else
  ko "B1-B3" "sauvegarde"
fi

extra_ports="$(ss -tulpn | awk 'NR>1 {print $5}' | grep -vE ':22$' || true)"
if dpkg -l unattended-upgrades 2>/dev/null | grep -q '^ii' && [[ -z "${extra_ports}" ]]; then
  ok "D1-D2" "updates auto + port 22 seul"
else
  ko "D1-D2" "D1/D2 (${extra_ports})"
fi

ww="$(find / -xdev -type f -perm -0002 2>/dev/null | head -n 1 || true)"
[[ -z "${ww}" ]] && ok "D3" "aucun fichier world-writable" || ko "D3" "world-writable: ${ww}"

printf '%d/%d tests reussis\n' "${PASS}" "${TOTAL}"
(( PASS == TOTAL )) && exit 0 || exit 1
