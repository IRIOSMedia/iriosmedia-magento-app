#!/usr/bin/env bash
# Updates the IRIOS Media module, Magento, Hyvä or the container images. It takes a backup first, puts the store in
# maintenance mode, updates, rebuilds (setup:upgrade, compilation, static content), flushes the cache and opens the
# store again.
#
#   bin/update.sh module [version|branch]   the IRIOS Media module (from IRIOS_MODULE_SOURCE in .env)
#   bin/update.sh magento <version>          a Magento patch, for example 2.4.8-p6
#   bin/update.sh hyva                       the Hyvä theme, to its latest compatible version
#   bin/update.sh images                     the container images (MariaDB, OpenSearch, Valkey, nginx, Caddy, PHP)
#
# Add --no-backup to skip the backup.
set -Eeuo pipefail
# shellcheck source=bin/lib.sh
source "$(dirname "$0")/lib.sh"

usage() { sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

backup=yes
args=()
for arg in "$@"; do
    if [[ $arg == --no-backup ]]; then backup=no; else args+=("$arg"); fi
done
set -- "${args[@]+"${args[@]}"}"
[[ $# -ge 1 ]] || usage
what="$1"
load_env

if [[ $what == images ]]; then
    say "Pulling and rebuilding the container images"
    docker compose pull db opensearch valkey valkey-sessions web caddy
    docker compose build --pull php
    docker compose up -d --wait db opensearch valkey valkey-sessions
    docker compose up -d
    echo "Done. The data volumes are kept."
    exit 0
fi

case "$what" in
    module)
        if [[ -n ${2:-} ]]; then
            if [[ ${IRIOS_MODULE_SOURCE:-git} == git ]]; then IRIOS_MODULE_REF="$2"; else IRIOS_MODULE_VERSION="$2"; fi
        fi
        ;;
    magento) [[ -n ${2:-} ]] || die "Which version? For example: bin/update.sh magento 2.4.8-p6" ;;
    hyva) ;;
    *) usage ;;
esac

[[ $backup == yes ]] && "$ROOT/bin/backup.sh"

say "Maintenance mode on"
magento maintenance:enable
trap 'warn "The update stopped. The store is still in maintenance mode: fix the error, run this again, or run bin/magento maintenance:disable."' ERR

case "$what" in
    module)
        install_irios_module
        ;;
    magento)
        say "Magento Open Source $2"
        composer require-commerce "magento/product-community-edition" "$2" --no-update
        composer update
        ;;
    hyva)
        say "Hyvä theme"
        composer update 'hyva-themes/*' --with-dependencies
        ;;
esac

say "Updating the database (setup:upgrade)"
magento setup:upgrade --keep-generated
build_production

trap - ERR
say "Maintenance mode off"
magento maintenance:disable

if [[ $what == module && -n ${2:-} ]]; then
    echo "Remember to write the new value in .env (IRIOS_MODULE_REF or IRIOS_MODULE_VERSION), so that bin/setup.sh keeps it."
fi
if [[ $what == magento ]]; then
    echo "Remember to set MAGENTO_VERSION=$2 in .env."
fi
magento --version
in_php composer show "$IRIOS_PACKAGE" 2>/dev/null | grep -E '^(name|versions|source|dist) ' || true
