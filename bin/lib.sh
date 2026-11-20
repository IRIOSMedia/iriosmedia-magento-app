# Shared by the bin/ scripts (sourced, not run). Reads .env and gives small helpers to run commands in the containers.
# shellcheck shell=bash

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

say() { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# Reads .env without running it as a script: KEY=value lines, an optional " # comment" after the value, and values in
# single or double quotes kept as they are written.
load_env() {
    [[ -f .env ]] || die "Missing .env: copy .env.example to .env and fill it in (see README.md)."
    local line key value
    while IFS= read -r line || [[ -n $line ]]; do
        [[ $line =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        if [[ $value =~ ^\'([^\']*)\' ]]; then
            value="${BASH_REMATCH[1]}"
        elif [[ $value =~ ^\"([^\"]*)\" ]]; then
            value="${BASH_REMATCH[1]}"
        else
            value="${value%%[[:space:]]#*}"
            value="${value%"${value##*[![:space:]]}"}"
        fi
        export "$key=$value"
    done < .env
}

# The address shoppers use for a store view domain, which depends on TLS_MODE:
#   letsencrypt, internal   https://, with HTTPS_PORT when it is not 443
#   cloudflare-flexible     https:// (Cloudflare serves HTTPS on 443)
#   http                    http://, with HTTP_PORT when it is not 80
store_url() {
    local scheme=https port=""
    case "${TLS_MODE:-letsencrypt}" in
        http)
            scheme=http
            [[ ${HTTP_PORT:-80} == 80 ]] || port=":$HTTP_PORT"
            ;;
        cloudflare-flexible) ;;
        *) [[ ${HTTPS_PORT:-443} == 443 ]] || port=":$HTTPS_PORT" ;;
    esac
    printf '%s://%s%s/' "$scheme" "$1" "$port"
}
uses_https() { [[ ${TLS_MODE:-letsencrypt} != http ]]; }

# Composer's credentials, from auth.json, passed to the container in the environment (never written there, never printed).
composer_auth() {
    [[ -f auth.json ]] || die "Missing auth.json: copy auth.json.example to auth.json and put your Magento access keys in it."
    tr -d '\n' < auth.json
}

# A command in the php container, as www-data (the owner of the store files).
in_php() { docker compose exec -T -u www-data php "$@"; }
# The same, with Composer's credentials.
in_php_auth() { docker compose exec -T -u www-data -e COMPOSER_AUTH="$(composer_auth)" php "$@"; }
magento() { in_php php bin/magento "$@"; }
composer() { in_php_auth composer --no-interaction --no-progress "$@"; }

# A SQL query in the database, with the credentials the db container already has.
sql() {
    docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_PASSWORD" mariadb -u"$MARIADB_USER" "$MARIADB_DATABASE" -N -B -e "$1"' sh "$1"
}

is_small() { [[ ${MEMORY_PROFILE:-standard} == small ]]; }

# --- IRIOS Media module ---------------------------------------------------------------------------------------------

IRIOS_PACKAGE=iriosmedia/module-irios-media

# Configures where Composer gets the module from (IRIOS_MODULE_SOURCE) and installs or updates it.
#   git        clones IRIOS_MODULE_REF into irios-media/source and uses its src/ folder as a Composer "path"
#              repository: the module's composer.json is in src/, not at the root of its git repository, so Composer
#              cannot read the git repository directly.
#   release    downloads the zip of the GitHub release into irios-media/artifacts, a Composer "artifact" repository.
#   packagist  the package from Packagist.
install_irios_module() {
    local source="${IRIOS_MODULE_SOURCE:-git}" version="${IRIOS_MODULE_VERSION:-}"
    local repo="${IRIOS_MODULE_REPO:-https://github.com/IRIOSMedia/iriosmedia-magento-module.git}"
    local constraint
    composer config --unset repositories.irios-media >/dev/null 2>&1 || true
    case "$source" in
        git)
            local ref="${IRIOS_MODULE_REF:-main}"
            say "IRIOS Media module from git: $repo ($ref)"
            # shellcheck disable=SC2016  # expanded by the container's shell
            in_php sh -c 'rm -rf irios-media/source && mkdir -p irios-media && git clone --quiet --depth 1 --branch "$1" "$2" irios-media/source' sh "$ref" "$repo"
            composer config repositories.irios-media '{"type": "path", "url": "irios-media/source/src", "options": {"symlink": false}}'
            constraint="@dev"
            ;;
        release)
            say "IRIOS Media module from the GitHub release ${version:-latest}"
            fetch_irios_release "$repo" "$version"
            composer config repositories.irios-media artifact irios-media/artifacts
            constraint="${version:-*}"
            ;;
        packagist)
            say "IRIOS Media module from Packagist ${version:-latest}"
            constraint="${version:-*}"
            ;;
        *) die "IRIOS_MODULE_SOURCE must be git, release or packagist (it is '$source')." ;;
    esac
    composer require --update-with-dependencies "$IRIOS_PACKAGE:$constraint"
    # A path or artifact repository can keep the same version while the code changes: reinstall to be sure
    composer reinstall "$IRIOS_PACKAGE" >/dev/null
    magento module:enable Irios_Media
}

# Downloads the release zip (asset iriosmedia-module-irios-media-<version>.zip) of a tag "1.2.3" or "v1.2.3", or of the
# latest release when no version is given.
fetch_irios_release() {
    local repo="$1" version="$2" slug
    slug="$(sed -E 's#^(https://github.com/|git@github.com:)##; s#\.git$##' <<<"$repo")"
    # shellcheck disable=SC2016  # PHP code
    in_php php -r '
        [, $slug, $version] = $argv;
        $paths = $version === "" ? ["latest"] : ["tags/$version", "tags/v$version"];
        $context = stream_context_create(["http" => ["header" => "User-Agent: magento-setup\r\nAccept: application/vnd.github+json\r\n", "ignore_errors" => true]]);
        foreach ($paths as $path) {
            $release = json_decode((string) @file_get_contents("https://api.github.com/repos/$slug/releases/$path", false, $context), true);
            foreach ($release["assets"] ?? [] as $asset) {
                if (preg_match("/^iriosmedia-module-irios-media-.+\\.zip$/", $asset["name"])) {
                    @mkdir("irios-media/artifacts", 0775, true);
                    $zip = file_get_contents($asset["browser_download_url"], false, $context);
                    if ($zip === false) { fwrite(STDERR, "Could not download {$asset["name"]}\n"); exit(1); }
                    file_put_contents("irios-media/artifacts/" . $asset["name"], $zip);
                    echo "Downloaded {$asset["name"]}\n";
                    exit(0);
                }
            }
        }
        fwrite(STDERR, "No release zip found for " . ($version ?: "the latest release") . " in $slug\n");
        exit(1);
    ' "$slug" "$version"
}

# --- Production build -----------------------------------------------------------------------------------------------

# Compiles the code and deploys the static files, the way production mode needs them. Long steps: on a small server
# they run one at a time, with a single job.
build_production() {
    local jobs="${STATIC_JOBS:-4}"
    is_small && jobs=1
    say "Production mode"
    magento deploy:mode:set production --skip-compilation
    say "Compiling the code (setup:di:compile)${MEMORY_PROFILE:+, $MEMORY_PROFILE server}"
    is_small && warn "Small server: this step can take 10 minutes or more."
    magento setup:di:compile
    say "Deploying static content (${MAGENTO_LOCALE:-en_US}, $jobs job(s))"
    is_small && warn "Small server: this step can take 10 minutes or more."
    local locales="${MAGENTO_LOCALE:-en_US}"
    [[ $locales == en_US ]] || locales="$locales en_US"   # the admin stays in English
    # shellcheck disable=SC2086
    magento setup:static-content:deploy -f --jobs "$jobs" $locales
    magento cache:flush
    # PHP keeps compiled code in memory (opcache without timestamp checks): reload the workers to use the new code
    docker compose kill -s USR2 php >/dev/null
}
