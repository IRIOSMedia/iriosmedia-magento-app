#!/usr/bin/env bash
# Restores a backup made by bin/backup.sh: the database, the media, app/etc/env.php and, when the backup has them,
# the same module versions (composer.json and composer.lock). Everything in the store now is replaced.
#
# On a new server, run bin/setup.sh first (with the same domains in .env), then restore.
#   bin/restore.sh backups/2026-01-31-020000
set -euo pipefail
# shellcheck source=bin/lib.sh
source "$(dirname "$0")/lib.sh"

dir="${1:-}"
[[ -n $dir && -f $dir/db.sql.gz ]] || die "Usage: bin/restore.sh backups/<date>  (a folder with db.sql.gz)"
load_env
in_php test -f bin/magento || die "Magento is not installed here yet: run bin/setup.sh first."

echo "This replaces the database, the media and app/etc/env.php of this store with the backup in $dir."
read -r -p "Type 'restore' to go on: " answer
[[ $answer == restore ]] || die "Nothing changed."

say "Maintenance mode on"
magento maintenance:enable || true

say "Configuration"
in_php sh -c 'cat > app/etc/env.php' < "$dir/env.php"
[[ -f $dir/config.php ]] && in_php sh -c 'cat > app/etc/config.php' < "$dir/config.php"
if [[ -f $dir/composer.json && -f $dir/composer.lock ]]; then
    in_php sh -c 'cat > composer.json' < "$dir/composer.json"
    in_php sh -c 'cat > composer.lock' < "$dir/composer.lock"
    say "Modules, as in the backup (composer install)"
    if in_php grep -q '"irios-media/source/src"' composer.json; then
        # The module came from git: get the same source back before Composer installs it
        install_irios_module
    elif in_php grep -q '"irios-media/artifacts"' composer.json; then
        # shellcheck disable=SC2016  # PHP code
        fetch_irios_release "${IRIOS_MODULE_REPO:-https://github.com/IRIOSMedia/iriosmedia-magento-module.git}" \
            "$(in_php php -r '$l = json_decode(file_get_contents("composer.lock"), true); foreach ($l["packages"] as $p) { if ($p["name"] === "iriosmedia/module-irios-media") { echo $p["version"]; } }')"
    fi
    composer install
fi

say "Database"
docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot -e "DROP DATABASE IF EXISTS \`$MARIADB_DATABASE\`; CREATE DATABASE \`$MARIADB_DATABASE\`; GRANT ALL ON \`$MARIADB_DATABASE\`.* TO \`$MARIADB_USER\`@\`%\`;"'
gunzip -c "$dir/db.sql.gz" | docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_PASSWORD" mariadb -u"$MARIADB_USER" "$MARIADB_DATABASE"'

say "Media"
in_php sh -c 'find pub/media -mindepth 1 -delete && tar -xzf - -C pub/media' < "$dir/media.tar.gz"

# The database settings in env.php are this server's (the backup may come from another one)
magento setup:config:set --db-host=db --db-name="${DB_NAME:-magento}" --db-user="${DB_USER:-magento}" \
    --db-password="$DB_PASSWORD" --session-save=redis --session-save-redis-host=valkey-sessions \
    --session-save-redis-db=0 --no-interaction >/dev/null

say "Updating the database (setup:upgrade)"
magento setup:upgrade --keep-generated
build_production
magento indexer:reindex

say "Maintenance mode off"
magento maintenance:disable
echo "Restored from $dir. If the domains changed, set the new base URLs (see README.md, Backups and restore)."
