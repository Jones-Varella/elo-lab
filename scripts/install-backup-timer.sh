#!/bin/bash
# Agenda o backup diário às 03:00 (UTC) com systemd. Rode uma vez na EC2, como root.
set -euo pipefail
cat > /etc/systemd/system/elo-lab-backup.service <<'UNIT'
[Unit]
Description=Backup do Postgres do elo-lab para o S3
[Service]
Type=oneshot
ExecStart=/bin/bash /opt/elo-lab/scripts/backup-postgres.sh
UNIT
cat > /etc/systemd/system/elo-lab-backup.timer <<'UNIT'
[Unit]
Description=Backup diário do elo-lab
[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true
[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable --now elo-lab-backup.timer
systemctl list-timers elo-lab-backup.timer
