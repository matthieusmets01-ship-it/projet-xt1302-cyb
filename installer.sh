#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DEV="${BACKUP_DEV:-/dev/sdb}"
BACKUP_MNT="${BACKUP_MNT:-/mnt/backup}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Erreur : ce script doit etre lance en root." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y --no-install-recommends openssh-server sudo acl rsync fail2ban nftables unattended-upgrades

chmod +x "${SCRIPT_DIR}/creer_comptes.sh"
"${SCRIPT_DIR}/creer_comptes.sh" "${SCRIPT_DIR}/comptes.csv" "${SCRIPT_DIR}/config/authorized_keys"

passwd -l root
for u in $(getent group sudo | cut -d: -f4 | tr ',' ' '); do
  if [[ "${u}" != "admin1" ]]; then
    gpasswd -d "${u}" sudo >/dev/null 2>&1 || true
  fi
done

install -d -m 750 /etc/sudoers.d
install -m 440 -o root -g root "${SCRIPT_DIR}/config/sudoers.d/pixelia" /etc/sudoers.d/pixelia
visudo -cf /etc/sudoers.d/pixelia

mkdir -p "${BACKUP_MNT}"
if [[ -b "${BACKUP_DEV}" ]]; then
  fs_type="$(blkid -s TYPE -o value "${BACKUP_DEV}" 2>/dev/null || true)"
  if [[ "${fs_type}" != "ext4" ]]; then
    mkfs.ext4 -F "${BACKUP_DEV}"
  fi
  uuid="$(blkid -s UUID -o value "${BACKUP_DEV}")"
  if ! grep -q "UUID=${uuid}" /etc/fstab; then
    echo "UUID=${uuid} ${BACKUP_MNT} ext4 defaults,noatime 0 2" >> /etc/fstab
  fi
  mountpoint -q "${BACKUP_MNT}" || mount "${BACKUP_MNT}"
fi
chown -R root:admins "${BACKUP_MNT}"
chmod 750 "${BACKUP_MNT}"

install -d -m 755 /etc/ssh/sshd_config.d
install -m 644 -o root -g root "${SCRIPT_DIR}/config/ssh/sshd_config.d/99-hardening.conf" /etc/ssh/sshd_config.d/99-hardening.conf

install -d -m 755 /etc/fail2ban/jail.d
install -m 644 -o root -g root "${SCRIPT_DIR}/config/fail2ban/jail.d/sshd.local" /etc/fail2ban/jail.d/sshd.local

install -m 644 -o root -g root "${SCRIPT_DIR}/config/nftables.conf" /etc/nftables.conf

install -d -m 755 /etc/systemd/journald.conf.d
install -m 644 -o root -g root "${SCRIPT_DIR}/config/journald.conf" /etc/systemd/journald.conf.d/99-persistent.conf

install -m 750 -o root -g root "${SCRIPT_DIR}/analyse_logs.sh" /usr/local/sbin/analyse_logs.sh
install -m 750 -o root -g root "${SCRIPT_DIR}/sauvegarde.sh" /usr/local/sbin/sauvegarde.sh

cat <<'CRON' > /etc/cron.d/pixelia-backup
0 2 * * * root /usr/local/sbin/sauvegarde.sh
CRON
chmod 644 /etc/cron.d/pixelia-backup

sshd -t
systemctl enable --now ssh
systemctl restart ssh
systemctl enable --now systemd-journald
systemctl restart systemd-journald
nft -f /etc/nftables.conf
systemctl enable --now nftables
systemctl enable --now fail2ban
systemctl restart fail2ban
systemctl enable --now unattended-upgrades

/usr/local/sbin/sauvegarde.sh
