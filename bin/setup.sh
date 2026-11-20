#!/usr/bin/env bash
# Installs the store, or brings an installed one in line with .env. Safe to run again: each step checks what is
# already done.
#
#   cp .env.example .env              # and fill it in
#   cp auth.json.example auth.json    # and put your Magento access keys in it
#   bin/setup.sh
#
# What it does, in order: checks the prerequisites; starts the containers; downloads Magento with Composer; installs it
# with the Luma domain as its address, over HTTPS; adds the sample data (optional); sets two-factor authentication;
# installs the IRIOS Media module; installs Hyvä and creates its store view (optional); switches to production mode
# (compiles the code and deploys the static files); reindexes; starts the web server and Caddy. At the end of the
# first installation, it prints the admin address and password, once.
set -euo pipefail
# shellcheck source=bin/lib.sh
source "$(dirname "$0")/lib.sh"

# --- Prerequisites ----------------------------------------------------------------------------------------------------

say "Checking prerequisites"
command -v docker >/dev/null || die "Docker is not installed (see README.md, Requirements)."
docker compose version >/dev/null 2>&1 || die "The Docker Compose plugin is not installed (see README.md, Requirements)."
load_env
composer_auth >/dev/null
grep -q '<public key' auth.json && die "auth.json still has the example values: put your Magento access keys in it."

[[ -n ${LUMA_DOMAIN:-} ]] || die "Set LUMA_DOMAIN in .env."
[[ ${TLS_MODE:-letsencrypt} =~ ^(letsencrypt|cloudflare-flexible|internal|http)$ ]] \
    || die "TLS_MODE must be letsencrypt, cloudflare-flexible, internal or http."
if [[ ${TLS_MODE:-letsencrypt} == letsencrypt ]]; then
    [[ -n ${ACME_EMAIL:-} && ${ACME_EMAIL} != *example.com ]] || die "Set ACME_EMAIL in .env to a real address (Let's Encrypt needs it)."
fi
if [[ -n ${BASIC_AUTH_USER:-} && ${BASIC_AUTH_HASH:-} != \$2* ]]; then
    die "BASIC_AUTH_USER is set but BASIC_AUTH_HASH is not a hash. Make one with: docker compose run --rm --no-deps caddy caddy hash-password"
fi
for var in DB_PASSWORD DB_ROOT_PASSWORD; do
    [[ ${!var:-} =~ ^change-me ]] && die "Set $var in .env (for example with: openssl rand -hex 24)."
done
[[ ${ADMIN_PATH:-admin} =~ ^[A-Za-z0-9_]+$ ]] || die "ADMIN_PATH in .env may only have letters, digits and _ (Magento rejects anything else), for example backoffice_7f3k."
[[ ${ADMIN_EMAIL:-} == *@* ]] || die "Set ADMIN_EMAIL in .env."
[[ ${TWO_FACTOR:-off} =~ ^(on|off)$ ]] || die "TWO_FACTOR must be on or off."
[[ ${SAMPLE_DATA:-yes} =~ ^(yes|no)$ ]] || die "SAMPLE_DATA must be yes or no."

HYVA_SOURCE="${HYVA_SOURCE:-github}"
HYVA_STORE_CODE="${HYVA_STORE_CODE:-hyva}"
case "$HYVA_SOURCE" in
    none) ;;
    github|packagist)
        [[ -n ${HYVA_DOMAIN:-} ]] || die "Set HYVA_DOMAIN in .env, or HYVA_SOURCE=none for no Hyvä store view."
        [[ $HYVA_DOMAIN != "$LUMA_DOMAIN" ]] || die "HYVA_DOMAIN must be different from LUMA_DOMAIN."
        if [[ $HYVA_SOURCE == packagist ]]; then
            [[ -n ${HYVA_PROJECT:-} ]] || die "HYVA_SOURCE=packagist needs HYVA_PROJECT (your project name at hyva.io)."
            if ! grep -q 'hyva-themes.repo.packagist.com' auth.json || grep -q '<optional: your Hyv' auth.json; then
                die "HYVA_SOURCE=packagist needs your Hyvä key in auth.json (see docs/hyva.md)."
            fi
        fi
        ;;
    *) die "HYVA_SOURCE must be github, packagist or none." ;;
esac

if is_small; then
    warn "Small memory profile: the heavy steps run one at a time. A first installation takes 30 to 60 minutes."
fi
if [[ $(uname -s) == Linux ]]; then
    total_kb=$(awk '/^(MemTotal|SwapTotal):/ {s += $2} END {print s}' /proc/meminfo)
    (( total_kb >= 3800000 )) || warn "Memory plus swap is under 4 GB: Magento's compilation may fail. Add swap (docs/aws.md)."
fi

LUMA_URL="$(store_url "$LUMA_DOMAIN")"

# --- Containers --------------------------------------------------------------------------------------------------------

say "Starting the containers (database, OpenSearch, Valkey, PHP, cron)"
docker compose up -d --build --wait db opensearch valkey valkey-sessions
docker compose up -d --build php cron

# --- Magento code ------------------------------------------------------------------------------------------------------

if ! in_php test -f bin/magento; then
    say "Downloading Magento Open Source ${MAGENTO_VERSION:-2.4.8-p5} (Composer, with your access keys)"
    is_small && warn "Small server: this step can take 10 minutes or more."
    # create-project needs an empty folder, and the store root already has pub/media (its own volume)
    in_php rm -rf /tmp/magento
    composer create-project --repository-url=https://repo.magento.com/ \
        "magento/project-community-edition=${MAGENTO_VERSION:-2.4.8-p5}" /tmp/magento
    in_php sh -c 'cp -a /tmp/magento/. /var/www/html/ && rm -rf /tmp/magento'
fi

# --- Installation ------------------------------------------------------------------------------------------------------

NEW_PASSWORD=""
if ! in_php test -f app/etc/env.php; then
    say "Installing Magento at $LUMA_URL"
    password="${ADMIN_PASSWORD:-}"
    if [[ -z $password ]]; then
        # Magento wants letters and digits: a random one, with both for sure
        password="$(openssl rand -base64 48 | LC_ALL=C tr -dc 'A-Za-z0-9' | cut -c1-20)7a"
        NEW_PASSWORD="$password"
    fi
    secure=0
    uses_https && secure=1
    magento setup:install \
        --base-url="$LUMA_URL" --base-url-secure="$LUMA_URL" \
        --use-secure="$secure" --use-secure-admin="$secure" --use-rewrites=1 \
        --backend-frontname="${ADMIN_PATH:-admin}" \
        --db-host=db --db-name="${DB_NAME:-magento}" --db-user="${DB_USER:-magento}" --db-password="$DB_PASSWORD" \
        --admin-firstname="${ADMIN_FIRSTNAME:-Store}" --admin-lastname="${ADMIN_LASTNAME:-Admin}" \
        --admin-email="$ADMIN_EMAIL" --admin-user="${ADMIN_USER:-admin}" --admin-password="$password" \
        --language="${MAGENTO_LOCALE:-en_US}" --currency="${MAGENTO_CURRENCY:-EUR}" --timezone="${MAGENTO_TIMEZONE:-UTC}" \
        --search-engine=opensearch --opensearch-host=opensearch --opensearch-port=9200 \
        --cache-backend=redis --cache-backend-redis-server=valkey --cache-backend-redis-db=0 \
        --page-cache=redis --page-cache-redis-server=valkey --page-cache-redis-db=1 \
        --session-save=redis --session-save-redis-host=valkey-sessions --session-save-redis-db=0
    echo "Installed."
fi

# --- Sample data ---------------------------------------------------------------------------------------------------------

if [[ ${SAMPLE_DATA:-yes} == yes ]] && ! in_php grep -q 'magento/module-catalog-sample-data' composer.json; then
    say "Sample data (Luma: products, categories, customers, CMS pages)"
    is_small && warn "Small server: this step can take 10 minutes or more."
    in_php_auth php bin/magento sampledata:deploy
    magento setup:upgrade --keep-generated
fi

# --- Settings --------------------------------------------------------------------------------------------------------------

say "Store settings (TLS_MODE=${TLS_MODE:-letsencrypt}, $LUMA_URL)"
# The addresses follow .env on every run, so changing a domain or TLS_MODE only needs this script again
magento config:set web/unsecure/base_url "$LUMA_URL"
magento config:set web/secure/base_url "$LUMA_URL"
secure=0
uses_https && secure=1
magento config:set web/secure/use_in_frontend "$secure"
magento config:set web/secure/use_in_adminhtml "$secure"
magento config:set web/url/redirect_to_base 1
magento config:set web/seo/use_rewrites 1
# Behind Caddy (and Cloudflare), Magento learns that the shopper used HTTPS from this header, so it does not redirect
# to https:// in a loop
magento config:set web/secure/offloader_header X-Forwarded-Proto
magento config:set catalog/search/engine opensearch >/dev/null

say "Two-factor authentication: ${TWO_FACTOR:-off}"
if [[ ${TWO_FACTOR:-off} == off ]]; then
    magento module:disable Magento_AdminAdobeImsTwoFactorAuth Magento_TwoFactorAuth >/dev/null || true
else
    magento module:enable Magento_TwoFactorAuth Magento_AdminAdobeImsTwoFactorAuth >/dev/null || true
fi

# --- IRIOS Media module ----------------------------------------------------------------------------------------------------

if ! in_php composer show "$IRIOS_PACKAGE" >/dev/null 2>&1; then
    install_irios_module
else
    echo "IRIOS Media module already installed (bin/update.sh module updates it)."
    magento module:enable Irios_Media >/dev/null
fi

# --- Hyvä store view -------------------------------------------------------------------------------------------------------

if [[ $HYVA_SOURCE != none ]]; then
    if ! in_php composer show hyva-themes/magento2-default-theme >/dev/null 2>&1; then
        say "Hyvä theme (from $HYVA_SOURCE)"
        if [[ $HYVA_SOURCE == packagist ]]; then
            composer config repositories.private-packagist composer "https://hyva-themes.repo.packagist.com/$HYVA_PROJECT/"
        else
            # Hyvä's public repositories, as listed in the Hyvä installation guide
            for package in magento2-theme-module magento2-default-theme magento2-default-theme-csp \
                magento2-base-layout-reset magento2-compat-module-fallback magento2-mollie-theme-bundle \
                magento2-luma-checkout magento2-theme-fallback magento2-order-cancellation-webapi \
                magento2-email-module; do
                composer config "repositories.hyva-themes/$package" git "https://github.com/hyva-themes/$package.git"
            done
        fi
        composer require hyva-themes/magento2-default-theme
    fi
fi

say "Updating the database (setup:upgrade)"
magento setup:upgrade --keep-generated >/dev/null

if [[ $HYVA_SOURCE != none ]]; then
    HYVA_URL="$(store_url "$HYVA_DOMAIN")"
    say "Hyvä store view '$HYVA_STORE_CODE' at $HYVA_URL"
    in_php php -- "$HYVA_STORE_CODE" "Hyvä" < docker/magento/create-hyva-store.php
    magento config:set --scope=websites --scope-code="$HYVA_STORE_CODE" web/unsecure/base_url "$HYVA_URL"
    magento config:set --scope=websites --scope-code="$HYVA_STORE_CODE" web/secure/base_url "$HYVA_URL"
    theme_id="$(sql "SELECT theme_id FROM theme WHERE area = 'frontend' AND theme_path = 'Hyva/default'")"
    [[ -n $theme_id ]] || die "The Hyvä theme is not registered (theme Hyva/default not found)."
    magento config:set --scope=stores --scope-code="$HYVA_STORE_CODE" design/theme/theme_id "$theme_id"
    # Checkout: Hyvä's default theme uses the Luma checkout (Hyvä theme fallback)
    magento config:set --scope=stores --scope-code="$HYVA_STORE_CODE" hyva_theme_fallback/general/enable 1 \
        || warn "Could not set the Hyvä checkout fallback: check it in Stores → Configuration → Hyvä Themes → Theme Fallback."
    magento config:set --scope=stores --scope-code="$HYVA_STORE_CODE" hyva_theme_fallback/general/theme_full_path frontend/Magento/luma \
        || true
fi

# --- Build -------------------------------------------------------------------------------------------------------------------

build_production

say "Reindexing"
magento indexer:set-mode schedule >/dev/null
magento indexer:reindex
magento cache:flush

say "Starting the web server and Caddy"
docker compose up -d web caddy

# --- Done ----------------------------------------------------------------------------------------------------------------------

say "Ready"
echo "Luma store:  $LUMA_URL"
[[ $HYVA_SOURCE != none ]] && echo "Hyvä store:  $(store_url "$HYVA_DOMAIN")"
echo "Admin:       ${LUMA_URL}${ADMIN_PATH:-admin}  (user: ${ADMIN_USER:-admin})"
if [[ -n $NEW_PASSWORD ]]; then
    echo
    echo "Admin password: $NEW_PASSWORD"
    echo "This is the only time it is shown: keep it in your password manager now."
fi
[[ -n ${BASIC_AUTH_USER:-} ]] && echo "The browser asks first for the password protection user ($BASIC_AUTH_USER)."
echo
echo "Next: connect the store to IRIOS Media (docs/irios-media.md)."
