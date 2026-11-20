#!/usr/bin/env bash
# Backs up the store into backups/<date and time>/:
#   db.sql.gz      the database
#   media.tar.gz   pub/media (product images, CMS uploads), without the resized image cache
#   env.php        app/etc/env.php: database settings and the encryption key. Without this key, a restored store
#                  cannot read the encrypted settings (passwords and tokens saved in the admin).
#   config.php, composer.json, composer.lock   the installed modules and their versions
#
# The folder holds passwords and the encryption key: keep it private. backups/ is git-ignored.
#   bin/backup.sh
set -euo pipefail
# shellcheck source=bin/lib.sh
source "$(dirname "$0")/lib.sh"
load_env

dir="backups/$(date +%Y-%m-%d-%H%M%S)"
umask 077
mkdir -p "$dir"

say "Database"
docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_PASSWORD" mariadb-dump -u"$MARIADB_USER" --single-transaction --quick --routines --triggers --no-tablespaces "$MARIADB_DATABASE"' \
    | gzip > "$dir/db.sql.gz"

say "Media"
in_php tar -czf - --exclude=catalog/product/cache -C pub/media . > "$dir/media.tar.gz"

say "Configuration"
for file in app/etc/env.php app/etc/config.php composer.json composer.lock; do
    in_php cat "$file" > "$dir/$(basename "$file")"
done

du -sh "$dir"
echo "Backup ready: $dir"
