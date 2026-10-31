#!/bin/sh
# Backup diário do banco do MusiConnect (roda no servidor, pelo cron).
#
# Gera /var/backups/musiconnect/musiconnect-AAAA-MM-DD.dump (formato do
# pg_dump -Fc; restaurar com pg_restore) e apaga os com mais de 14 dias.
#
# Instalação (uma vez, como root):
#   ln -s /opt/musiconnect/deploy/backup.sh /etc/cron.daily/musiconnect-backup
set -eu

DIR=/var/backups/musiconnect
KEEP_DAYS=14
FILE="$DIR/musiconnect-$(date +%F).dump"

mkdir -p "$DIR"
chmod 700 "$DIR"

docker exec musiconnect_db pg_dump -U postgres -d musiconnect -Fc > "$FILE.tmp"
mv "$FILE.tmp" "$FILE"
chmod 600 "$FILE"

find "$DIR" -name 'musiconnect-*.dump' -mtime +"$KEEP_DAYS" -delete
