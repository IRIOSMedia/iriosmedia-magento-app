# Magento test store with IRIOS Media

Magento 2 test store running the IRIOS Media module, with a Luma and a Hyvä store view: Docker, HTTPS and
password-protected access, connected to IRIOS Media. Includes the guide to deploy and update it on AWS.

This repository is for two kinds of people:

- **Retailers** who run Magento 2 Open Source and want to see, or reproduce, a store that works with the
  [IRIOS Media module](https://github.com/IRIOSMedia/iriosmedia-magento-module). You can use it as a guide for your
  own store, or run it as a test store next to your real one.
- **Anyone who needs a Magento test store** with the IRIOS Media module on a cloud server, for example to try new
  versions of the module before they reach a real store.

IRIOS Media is a retail media network: it lets brands advertise inside a retailer's online store. The module adds
shopper events, Sponsored Products, display ads (image and video) and push notifications to Magento.

## Contents

- [What you get](#what-you-get)
- [Requirements](#requirements)
- [Quick start on your computer](#quick-start-on-your-computer)
- [Deploy on a server](#deploy-on-a-server)
- [Connect to IRIOS Media](#connect-to-irios-media)
- [Everyday commands](#everyday-commands)
- [Updating](#updating)
- [Backups and restore](#backups-and-restore)
- [Two-factor authentication](#two-factor-authentication)
- [Troubleshooting](#troubleshooting)
- [Security notes](#security-notes)
- [Repository layout](#repository-layout)
- [License](#license)

## What you get

One command, `bin/setup.sh`, gives you a complete store:

- **Magento Open Source 2.4.8** (the patch you choose in `.env`, 2.4.8-p5 by default), in production mode.
- **Sample data** (optional): the Luma demo catalog, with products, categories, customers and CMS pages. It gives
  the ads something to show and the events something to track.
- **Two store views**, each with its own domain:
  - **Luma** at one domain (for example `shop.example.com`), Magento's standard theme;
  - **Hyvä** at another domain (for example `hyva.shop.example.com`), the popular lightweight theme. It is optional;
    see [docs/hyva.md](docs/hyva.md).
- **The IRIOS Media module** (`iriosmedia/module-irios-media`), installed with Composer from a release or from a
  branch.
- **HTTPS** with automatic Let's Encrypt certificates, renewed by [Caddy](https://caddyserver.com) on its own; or,
  if you prefer, behind Cloudflare's proxy (SSL/TLS mode "Flexible"), with no certificate on the server.
- **Password protection** (optional): the browser asks for a user name and password before it shows anything (HTTP
  basic auth). Useful to keep a test store away from search engines and visitors.
- **Cron**: Magento's scheduled tasks run every minute, including the module's own jobs.
- **Backups** of the database, the media and the configuration with one command, and a restore command.

The store runs in Docker containers:

| Service | What it does |
|---|---|
| `caddy` | The only one reachable from outside (ports 80 and 443). HTTPS (or plain HTTP behind Cloudflare), password protection, passes requests to `web`. |
| `web` | nginx with Magento's own configuration (`nginx.conf.sample`). Picks the store view from the domain. |
| `php` | PHP-FPM 8.3 running Magento, with Composer. |
| `cron` | The same PHP image, running `bin/magento cron:run` every minute. |
| `db` | MariaDB 11.4 (long-term support). |
| `opensearch` | OpenSearch 2, the catalog search. |
| `valkey` | Cache and full page cache (Valkey is the open source successor of Redis). |
| `valkey-sessions` | Sessions, in their own instance so that a full cache never logs anyone out. |

The data lives in Docker named volumes (`code`, `media`, `db`, `opensearch`, `sessions`, `caddy-data`,
`caddy-config`), so it survives restarts and image updates.

## Requirements

**On any machine:**

- Docker Engine 24 or later with the Docker Compose plugin (`docker compose version` should work). On a Mac or
  Windows, Docker Desktop includes both.
- Memory: 8 GB is comfortable. A 2 GB server works for a quiet test store with the "small" memory profile and swap
  (see [Server size](docs/aws.md#1-choose-the-server-size)).
- Disk: 40 GB.
- **Magento access keys** (free): Magento is downloaded with Composer from Adobe's repository, which needs them.
  1. Sign in, or create an account, at https://commercemarketplace.adobe.com.
  2. Go to **My Profile → Access Keys → Create A New Access Key**, and give it a name, for example `test store`.
  3. Copy the public and private keys. You will put them in `auth.json`.

**On a server, also:**

- Two domain names (one per store view) whose DNS you can change.
- Ports 80 and 443 open to the internet: Let's Encrypt checks them to issue the certificates. Behind Cloudflare, port
  80 open to Cloudflare only.

## Quick start on your computer

Use this to try the store on your own computer before you put it on a server. It uses `*.localhost` domains, which
browsers send to your own computer without any setup, and HTTPS certificates from Caddy's own local authority.

1. Clone the repository:

   ```bash
   git clone https://github.com/IRIOSMedia/iriosmedia-magento-app.git
   cd iriosmedia-magento-app
   ```

2. Create your settings from the example:

   ```bash
   cp .env.example .env
   cp auth.json.example auth.json
   ```

3. Edit `.env` and change these values:

   ```dotenv
   LUMA_DOMAIN=luma.localhost
   HYVA_DOMAIN=hyva.localhost
   TLS_MODE=internal
   ADMIN_EMAIL=you@example.com
   DB_PASSWORD=<output of: openssl rand -hex 24>
   DB_ROOT_PASSWORD=<output of: openssl rand -hex 24>
   ```

   If ports 80 or 443 are already used on your computer (for example by another local store), also set
   `HTTP_PORT=8080` and `HTTPS_PORT=8443`. The store is then at `https://luma.localhost:8443/`.

   `TLS_MODE=http` is the other local option: plain HTTP, with no certificate warnings, but without push
   notifications, which need HTTPS.

4. Edit `auth.json`: put your Magento public key as `username` and your private key as `password` under
   `repo.magento.com`. Leave the Hyvä entry as it is.

5. Run the setup:

   ```bash
   bin/setup.sh
   ```

   The first run downloads Magento and its sample data (a few gigabytes) and installs everything, so it takes a while:
   about 20 to 40 minutes. At the end, it prints the addresses and the admin password. The password is also kept in
   `admin-password.txt` (readable only by you), in case the run stops halfway: save it in your password manager and
   then delete that file.

6. Open `https://luma.localhost/` (and `https://hyva.localhost/`). Your browser warns that the certificate is not
   trusted, because it comes from Caddy's local authority. You have two options:
   - **Option 1:** accept the warning in the browser. Enough to look around.
   - **Option 2:** trust Caddy's local authority, which you need to test push notifications (browsers refuse a
     service worker over an untrusted certificate). Copy the certificate out of the container and add it to your
     system's trusted certificates (on a Mac: double-click it, then in Keychain Access set it to "Always Trust"):

     ```bash
     docker compose cp caddy:/data/caddy/pki/authorities/local/root.crt ./caddy-local-root.crt
     ```

To stop the store, run `docker compose stop`. To start it again, run `docker compose up -d`.

## Deploy on a server

[docs/aws.md](docs/aws.md) takes you step by step through running the store on Amazon Web Services (EC2): choosing
the server, opening the ports, DNS, installing Docker, running the setup, certificates, updates and backups, and
[running behind Cloudflare](docs/aws.md#15-behind-cloudflare). The same steps work on any Linux server with Docker.

## Connect to IRIOS Media

[docs/irios-media.md](docs/irios-media.md) explains what IRIOS Media gives you, how to fill in each IRIOS Media page
of the admin for each store view, consent, how to give the IRIOS Media sync service access to the store, push
notifications, and a checklist to verify that everything works.

## Everyday commands

Run them from the repository folder.

| Command | What it does |
|---|---|
| `bin/magento <command>` | Runs Magento's `bin/magento` in the `php` container, for example `bin/magento cache:flush`. |
| `docker compose ps` | Shows the services and whether they are healthy. |
| `docker compose logs -f caddy web php` | Follows the logs of those services. |
| `docker compose stop` / `docker compose up -d` | Stops and starts the store. The data stays in the volumes. |
| `bin/setup.sh` | Brings the store in line with `.env`. Safe to run again at any time. |
| `bin/update.sh ...` | Updates the module, Magento, Hyvä or the images ([Updating](#updating)). |
| `bin/backup.sh` | Makes a backup ([Backups and restore](#backups-and-restore)). |

## Updating

`bin/update.sh` takes a backup first, puts the store in maintenance mode, updates, runs `setup:upgrade`, compiles
the code, deploys the static files, flushes the cache and opens the store again. Add `--no-backup` to skip the
backup.

### The IRIOS Media module

Where the module comes from depends on `IRIOS_MODULE_SOURCE` in `.env`:

- **Option 1: `git`** (the default until the module's first release). The module is installed from a branch or tag of
  its GitHub repository, set in `IRIOS_MODULE_REF` (`main` by default). To get the latest code of that branch:

  ```bash
  bin/update.sh module
  ```

  To switch to another branch or tag, give it as an argument, and then write it in `IRIOS_MODULE_REF` in `.env`
  so that `bin/setup.sh` keeps it:

  ```bash
  bin/update.sh module my-branch
  ```

- **Option 2: `release`**. The module is installed from the zip of a GitHub release. To update to a version (or to
  the latest one, without a version):

  ```bash
  bin/update.sh module 1.2.0
  ```

  Then write it in `IRIOS_MODULE_VERSION` in `.env`.

- **Option 3: `packagist`**, once the package is published on Packagist. It works like Option 2.

To move from `git` to `release` (for example when the first release is out), set `IRIOS_MODULE_SOURCE=release` and
`IRIOS_MODULE_VERSION=<version>` in `.env`, then run `bin/update.sh module`.

The admin also tells you when a new version of the module is out: a notice appears in the notifications (the bell).

### Magento

Adobe publishes security patches for 2.4.8 as `2.4.8-p<N>`. Read their release notes first, then:

```bash
bin/update.sh magento 2.4.8-p6
```

Then set `MAGENTO_VERSION=2.4.8-p6` in `.env`.

### Hyvä

```bash
bin/update.sh hyva
```

### Container images

To get the latest fixes of MariaDB 11.4, OpenSearch, Valkey, nginx, Caddy and the PHP base image, within the
versions pinned in `docker-compose.yml`:

```bash
bin/update.sh images
```

### This repository

When this repository changes (for example a new nginx or Caddy setting), get the changes and apply them:

```bash
git pull
docker compose up -d --build
```

## Backups and restore

**Make a backup:**

```bash
bin/backup.sh
```

It creates a folder `backups/<date-time>/` with:

- `db.sql.gz`: the database;
- `media.tar.gz`: the product images and uploads (`pub/media`), without the resized image cache, which Magento
  rebuilds by itself;
- `env.php`: database settings and **the encryption key**. Magento encrypts some settings with it (passwords and
  tokens saved in the admin), so a restore needs the same key;
- `config.php`, `composer.json` and `composer.lock`: which modules are installed, and their versions.

The folder holds passwords and the encryption key, so keep it private. `backups/` is git-ignored. To copy backups
off the server, see [Backups to S3](docs/aws.md#11-backups) in the AWS guide.

To take one every night, add a line to the server's crontab (`crontab -e`), with the path of your copy of this
repository. This one runs at 02:00 and deletes backups older than 14 days:

```cron
0 2 * * * cd /home/ubuntu/iriosmedia-magento-app && mkdir -p backups && bin/backup.sh >> backups/backup.log 2>&1 && find backups -mindepth 1 -maxdepth 1 -type d -mtime +14 -exec rm -rf {} +
```

**Restore a backup:**

```bash
bin/restore.sh backups/2026-01-31-020000
```

It asks you to type `restore` to confirm, because it replaces the database, the media and the configuration of the
store. On a new server, run `bin/setup.sh` first (with the same `.env`), then copy the backup folder into `backups/`
and restore it.

If the new store has different domains, set them after the restore:

```bash
bin/magento config:set web/unsecure/base_url https://<new Luma domain>/
bin/magento config:set web/secure/base_url https://<new Luma domain>/
bin/magento config:set --scope=websites --scope-code=hyva web/unsecure/base_url https://<new Hyvä domain>/
bin/magento config:set --scope=websites --scope-code=hyva web/secure/base_url https://<new Hyvä domain>/
bin/magento cache:flush
```

## Two-factor authentication

Magento can ask admins for a second factor (an authenticator app code) after the password. `TWO_FACTOR` in `.env`
decides it.

- **`TWO_FACTOR=off`** (the default) suits a test store behind password protection: the store is already behind a
  password, and Magento's first two-factor setup sends an email, which a test store usually cannot send.
- **`TWO_FACTOR=on`** suits a store open to the public. Before you switch it on, set up the authenticator app from
  the command line, so you need no email:
  1. Set `TWO_FACTOR=on` in `.env` and run `bin/setup.sh`.
  2. Choose Google Authenticator as the method (it works with any authenticator app):
     `bin/magento config:set twofactorauth/general/force_providers google`
  3. Make a secret for your admin user and give it to Magento:

     ```bash
     secret=$(LC_ALL=C tr -dc 'A-Z2-7' < /dev/urandom | head -c 32)
     bin/magento security:tfa:google:set-secret admin "$secret"
     echo "$secret"
     ```

  4. In your authenticator app, add an account by entering that secret by hand (type "time based").
  5. Log in to the admin: it asks for the code from the app.

## Troubleshooting

Look for the symptom here. `docker compose logs <service>` usually tells you more.

| Symptom | Cause and fix |
|---|---|
| `bin/setup.sh` stops at the download with "authentication required" or 401 | The Magento keys in `auth.json` are wrong or still the example ones. Check them in your Adobe account (My Profile → Access Keys). |
| The browser says the site cannot be reached | Check `docker compose ps`: `caddy` and `web` should be running. On a server, check that ports 80 and 443 are open (security group) and that the DNS A records point to the server. |
| Certificate error on a server | Let's Encrypt could not check the domain. `docker compose logs caddy` gives the reason. Usually the DNS does not point to the server yet, or port 80 is closed. Caddy retries by itself; after fixing it, run `docker compose restart caddy`. |
| Redirect loop, or links with `http://` | Magento does not see HTTPS. Check `bin/magento config:show web/secure/offloader_header` (it should be `X-Forwarded-Proto`) and that `TLS_MODE` matches how the store is reached; after changing it, run `bin/setup.sh` again. Behind Cloudflare, the SSL/TLS mode must be Flexible and the server must be reached only through Cloudflare. |
| The Hyvä domain shows the Luma store | nginx did not get the Hyvä domain: check `HYVA_DOMAIN` in `.env` and run `docker compose up -d web`. |
| Pages without styles, 404 for `.js` or `.css` files | The static files were not deployed for a theme or language. Run `bin/setup.sh` again; it deploys them for `MAGENTO_LOCALE` and English. |
| "There has been an error processing your request" | Magento logged the error. Read it with `docker compose exec php tail -n 50 var/log/exception.log`, or open the report whose number the page shows: `docker compose exec php cat var/report/<number>`. |
| The store shows "Service Temporarily Unavailable" | It is in maintenance mode, usually because an update stopped. Fix what the update reported and run it again, or run `bin/magento maintenance:disable`. |
| `setup:di:compile` or static content stops with "Killed" | Not enough memory. Add swap, or use the small memory profile ([Server size](docs/aws.md#1-choose-the-server-size)). |
| OpenSearch keeps restarting | Not enough memory for its heap: lower `OPENSEARCH_HEAP`, or add memory. On Linux, also check `vm.max_map_count` ([AWS guide](docs/aws.md#5-prepare-the-server)). |
| Scheduled tasks do not run | `docker compose logs cron`. The cron waits while the store is in maintenance mode. |
| The admin password is lost | Create a new admin: `bin/magento admin:user:create --admin-user=<name> --admin-password=<password> --admin-email=<email> --admin-firstname=<first> --admin-lastname=<last>` |

For problems with the IRIOS Media module itself (ads, events, push), see the checklist in
[docs/irios-media.md](docs/irios-media.md#9-verify-that-everything-works).

## Security notes

- **Secrets stay on the server.** `.env` (passwords) and `auth.json` (Magento and Hyvä keys) are git-ignored. Keep
  them on the server only, out of commits and issues. `bin/setup.sh` passes `auth.json` to Composer in the environment of
  each command and never prints it.
- **Password protection and the REST API.** With password protection on, every path asks for the password except
  `BASIC_AUTH_OPEN_PATHS` (by default `/rest/*`, `/irios-sw.js` and `/media/*`):
  - `/rest/*` is open because the IRIOS Media sync service reads the store through Magento's REST API and
    authenticates with its Magento integration token, in the `Authorization` header. A browser password travels in
    that same header, so the two cannot be combined. Magento checks the token on every call, and the integration
    only reaches what you allow it to.
  - `/irios-sw.js` is the push service worker. Browsers check it for updates in the background without the password.
  - `/media/*` holds the product images. The catalog sent to IRIOS Media points to them, so IRIOS Media must be able
    to fetch them.
    It is a public script with no data.

  Keep in mind that Magento's public REST endpoints (the ones a storefront uses without logging in) are then
  reachable without the password, as in any public Magento store.
- **Only Caddy is exposed.** The database, OpenSearch, Valkey, PHP and nginx are only reachable inside the Docker
  network. OpenSearch runs without its security plugin for that reason, so keep its port private.
- **SSH** (port 22) should only be open to your own IP address (see the AWS guide).
- **Admin path.** `ADMIN_PATH` in `.env` moves the admin away from `/admin`, which bots try first. Set it before the
  first setup, or change it later with `bin/magento setup:config:set --backend-frontname=<path>`.
- **Backups** contain the database and the encryption key: store them privately (an S3 bucket with public access
  blocked, for example).
- **Updates.** Apply Magento security patches when Adobe publishes them ([Updating](#updating)), and update the
  images now and then (`bin/update.sh images`).
- **Real customer data.** This is a test store: use the sample data or test accounts, not real customers' data.

## Repository layout

```text
.
├── README.md                     this guide
├── LICENSE                       GPL-2.0-or-later
├── docker-compose.yml            the services, volumes and settings (all values from .env)
├── .env.example                  every setting, explained; copy it to .env
├── auth.json.example             Composer keys (Magento, optional Hyvä); copy it to auth.json
├── bin/
│   ├── setup.sh                  installs the store, or brings it in line with .env (safe to re-run)
│   ├── update.sh                 updates the module, Magento, Hyvä or the images
│   ├── backup.sh                 backs up the database, media and configuration into backups/
│   ├── restore.sh                restores a backup
│   ├── magento                   runs bin/magento in the php container
│   ├── cloudflare-ips.sh         refreshes Cloudflare's address ranges (TLS_MODE=cloudflare-flexible)
│   └── lib.sh                    helpers shared by the scripts
├── docker/
│   ├── caddy/                    one Caddyfile per TLS_MODE, plus the shared password protection and reverse proxy
│   ├── nginx/                    nginx for Magento: store view per domain, push service worker, HTTPS behind Caddy
│   ├── php/                      PHP-FPM 8.3 image: extensions, php.ini, worker pool
│   └── magento/                  the script that creates the Hyvä website, store and store view
└── docs/
    ├── aws.md                    deploying and running the store on AWS EC2
    ├── irios-media.md            connecting the store to IRIOS Media
    └── hyva.md                   the Hyvä store view
```

## License

[GPL-2.0-or-later](LICENSE), the same as the IRIOS Media module. Magento Open Source, Hyvä and the container images
keep their own licenses: this repository only contains the configuration and scripts that put them together.
