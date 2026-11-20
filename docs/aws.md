# Running the store on AWS (EC2)

This guide is for whoever puts the store on a server in Amazon Web Services: a retailer who wants a test store next
to their real one, or a team that keeps a test store for the IRIOS Media module. It goes from an empty AWS account to
a store with HTTPS, and then covers updates, backups and monitoring.

You need an AWS account with permission to create EC2 instances, and two domain names (one per store view) whose DNS
records you can change. In the examples, the domains are `shop.example.com` (Luma) and `hyva.shop.example.com`
(Hyvä): use your own.

The same steps work on any Linux server with Docker; only steps 1 to 4 are specific to AWS.

## Contents

1. [Choose the server size](#1-choose-the-server-size)
2. [Launch the instance](#2-launch-the-instance)
3. [Give it a fixed IP address](#3-give-it-a-fixed-ip-address)
4. [Point the domains to it](#4-point-the-domains-to-it)
5. [Prepare the server](#5-prepare-the-server)
6. [Install Docker](#6-install-docker)
7. [Get the repository and fill in the settings](#7-get-the-repository-and-fill-in-the-settings)
8. [Run the setup](#8-run-the-setup)
9. [Check HTTPS](#9-check-https)
10. [Updates](#10-updates)
11. [Backups](#11-backups)
12. [Monitoring](#12-monitoring)
13. [Resize the server later](#13-resize-the-server-later)
14. [Costs](#14-costs)
15. [Behind Cloudflare](#15-behind-cloudflare)

**Two ways to serve HTTPS.** Read this before step 2, because it changes the firewall and DNS steps:

- **Option 1: Let's Encrypt on the server** (`TLS_MODE=letsencrypt`, the default). The domains point straight to the
  server, and Caddy gets and renews the certificates by itself. Follow the guide as it is.
- **Option 2: behind Cloudflare** (`TLS_MODE=cloudflare-flexible`). The domains are in Cloudflare with its proxy on;
  Cloudflare serves HTTPS to shoppers and talks to the server over plain HTTP. Follow the guide, with the changes in
  [step 15](#15-behind-cloudflare) for steps 2, 4 and 7.

## 1. Choose the server size

Magento needs most of its memory for three things: the search engine (OpenSearch), the database, and PHP. The
heaviest moments are not the visits but the builds: compiling the code and deploying the static files after an
install or update. That is why the size is mostly about memory.

| Instance | vCPU / memory | When to use it |
|---|---|---|
| `t3.small` | 2 / 2 GB | Possible for a quiet test store, with the **small memory profile** and **4 GB of swap**. Installs and updates are slow: a build takes 15 to 20 minutes. |
| `t3.medium` | 2 / 4 GB | The comfortable minimum for a test store, with the default settings and 2 to 4 GB of swap. |
| `t3.large` | 2 / 8 GB | **Recommended** for real traffic, or a test store that several people use at once. The defaults in `.env.example` are made for it. |

T3 instances run on CPU credits: they can use the full CPU for a while and then slow down to a baseline. The builds
use the full CPU for many minutes, so make sure the instance uses **Unlimited** credits; otherwise a build can slow to
a crawl halfway. T3 instances start as Unlimited by default. To check it: EC2 → **Instances** → select the instance
→ **Actions → Instance settings → Change credit specification** → tick **Unlimited** → **Save**.

### The small memory profile (2 GB)

On a 2 GB server, set these values in `.env` (they are also in the comments of `.env.example`):

```dotenv
MEMORY_PROFILE=small
OPENSEARCH_HEAP=512m
DB_BUFFER_POOL_SIZE=128M
DB_MAX_CONNECTIONS=50
DB_TMP_TABLE_SIZE=16M
DB_SORT_BUFFER_SIZE=256K
DB_JOIN_BUFFER_SIZE=256K
PHP_FPM_PM=ondemand
PHP_FPM_MAX_CHILDREN=3
PHP_FPM_IDLE_TIMEOUT=30s
VALKEY_MAXMEMORY=64mb
STATIC_JOBS=1
```

What each one does:

- `MEMORY_PROFILE=small` makes `bin/setup.sh` and `bin/update.sh` run the heavy steps one at a time, with a single job
  for the static files, and warn you that they take long.
- OpenSearch gets a 512 MB heap, and the database a 128 MB buffer pool, with small per-connection buffers and at
  most 50 connections.
- PHP starts workers only when requests come in (`ondemand`), at most 3, and stops them after 30 seconds idle.
- The cache keeps at most 64 MB and drops the least used entries when full. Sessions are in a separate instance that
  never drops anything, so a full cache never logs anyone out.

Optionally, you can also cap each container's memory with `DB_MEM_LIMIT`, `OPENSEARCH_MEM_LIMIT` and `PHP_MEM_LIMIT`
(for example `768m`). A container that reaches its cap is restarted, so leave them at `0` (no cap) unless you need to
protect the other services.

## 2. Launch the instance

1. In the AWS console, open **EC2** and choose the region closest to your shoppers (top right).
2. Click **Launch instances**.
3. **Name**: for example `magento-test-store`.
4. **Application and OS Images**: **Ubuntu**, then **Ubuntu Server 24.04 LTS** or **26.04 LTS**, architecture
   **64-bit (x86)**. Both work the same way with this guide.
5. **Instance type**: the one you chose in step 1, for example `t3.large`.
6. **Key pair**: choose one you have, or click **Create new key pair** (type ED25519, format `.pem`) and keep the
   downloaded file safe. You need it to connect with SSH.
7. **Network settings** → **Edit** → **Create security group**, named for example `magento-test-store`, with these
   inbound rules:

   | Type | Port | Source | Why |
   |---|---|---|---|
   | SSH | 22 | **My IP** | Only you can connect to the server. |
   | HTTP | 80 | Anywhere (0.0.0.0/0 and ::/0) | Let's Encrypt checks the domain here; Caddy redirects visitors to HTTPS. |
   | HTTPS | 443 | Anywhere (0.0.0.0/0 and ::/0) | The store. |

   If your IP address changes, update the SSH rule (EC2 → **Security Groups** → the group → **Edit inbound rules**).
   Behind Cloudflare, HTTP and HTTPS are open to Cloudflare only ([step 15](#15-behind-cloudflare)).
8. **Configure storage**: **40 GiB**, volume type **gp3**. Magento, its sample data, the images, the database and a
   few local backups fit comfortably.
9. Click **Launch instance**.

## 3. Give it a fixed IP address

An instance gets a new public IP address each time it is stopped and started. An Elastic IP stays the same, so the DNS
records keep working.

1. EC2 → **Network & Security → Elastic IPs** → **Allocate Elastic IP address** → **Allocate**.
2. Select the new address → **Actions → Associate Elastic IP address**.
3. **Instance**: your instance → **Associate**.

Write down this address: it is the one you use for DNS and SSH. In this guide it appears as `203.0.113.10`.

## 4. Point the domains to it

In the DNS of your domains (Route 53 or your DNS provider), create one **A record** per store view, both pointing to
the Elastic IP:

| Name | Type | Value |
|---|---|---|
| `shop.example.com` | A | `203.0.113.10` |
| `hyva.shop.example.com` | A | `203.0.113.10` |

Check them from your computer before going on (the answer must be the Elastic IP):

```bash
dig +short shop.example.com
dig +short hyva.shop.example.com
```

Let's Encrypt can only issue the certificates once these answer correctly. Behind Cloudflare, the records are
created in Cloudflare instead, and `dig` answers Cloudflare's addresses ([step 15](#15-behind-cloudflare)).

## 5. Prepare the server

Connect with SSH, using your key file and the Elastic IP:

```bash
chmod 600 ~/Downloads/my-key.pem
ssh -i ~/Downloads/my-key.pem ubuntu@203.0.113.10
```

Update the system:

```bash
sudo apt-get update && sudo apt-get -y upgrade
sudo reboot   # if the upgrade asks for it; connect again after a minute
```

**Swap.** Swap is disk space the system uses as extra memory when it runs out. It keeps a build from failing with
"Killed" on a small server. Create a 4 GB swap file (on a 2 GB server this is required; on bigger ones it is a cheap
safety net):

```bash
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
free -h   # the "Swap" line now shows 4.0Gi
```

**System settings for OpenSearch and swap.** OpenSearch needs more memory maps than Ubuntu allows by default, and a
low swappiness keeps the system from swapping while there is still memory free:

```bash
printf 'vm.max_map_count=262144\nvm.swappiness=10\n' | sudo tee /etc/sysctl.d/99-magento.conf
sudo sysctl --system
```

## 6. Install Docker

These are Docker's official commands for Ubuntu (from docs.docker.com, "Install Docker Engine on Ubuntu"). They read
the Ubuntu release name from the system (for example `noble` for 24.04), so the same commands work on
both:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

Let your user run Docker without `sudo`, then log out and in again so it takes effect:

```bash
sudo usermod -aG docker "$USER"
exit
```

After connecting again, check it:

```bash
docker compose version
```

If `apt-get update` says that Docker's repository has no `Release` file for your Ubuntu version, Docker has not
published packages for that release yet. Check the list of release names at https://download.docker.com/linux/ubuntu/dists/,
and until yours appears, use the previous LTS name in `/etc/apt/sources.list.d/docker.list` (for example `noble`),
then run `sudo apt-get update` again.

Docker starts by itself when the server boots, and the containers restart with it.

## 7. Get the repository and fill in the settings

```bash
git clone https://github.com/IRIOSMedia/iriosmedia-magento-app.git
cd iriosmedia-magento-app
cp .env.example .env
cp auth.json.example auth.json
```

**`.env`.** Open it with `nano .env` and change at least:

| Setting | Value |
|---|---|
| `LUMA_DOMAIN` | Your Luma domain, for example `shop.example.com` |
| `HYVA_DOMAIN` | Your Hyvä domain, for example `hyva.shop.example.com` |
| `TLS_MODE` | `letsencrypt` (the default), or `cloudflare-flexible` behind Cloudflare ([step 15](#15-behind-cloudflare)) |
| `ACME_EMAIL` | Your email: Let's Encrypt writes here if a certificate has a problem (not used behind Cloudflare) |
| `ADMIN_EMAIL` | The admin's email |
| `ADMIN_PATH` | A less obvious admin path than `admin`, for example `backoffice-7f3k` |
| `DB_PASSWORD`, `DB_ROOT_PASSWORD` | Each one the output of `openssl rand -hex 24` |
| Memory settings | The small profile values on a 2 GB server ([step 1](#the-small-memory-profile-2-gb)) |

**Password protection** (recommended for a test store). Choose a user name, and make the hash of a password:

```bash
docker compose run --rm --no-deps caddy caddy hash-password
```

It asks for the password twice and prints a hash that starts with `$2a$`. Put both in `.env`, with the hash between
single quotes:

```dotenv
BASIC_AUTH_USER=preview
BASIC_AUTH_HASH='$2a$14$...the hash...'
```

**`auth.json`.** Open it with `nano auth.json` and put your Magento public key as `username` and your private key as
`password` under `repo.magento.com` (see [Requirements](../README.md#requirements)). Leave the Hyvä entry as it is,
unless you use `HYVA_SOURCE=packagist` ([docs/hyva.md](hyva.md)).

Make both files readable only by you:

```bash
chmod 600 .env auth.json
```

## 8. Run the setup

Run it inside `tmux`, so it keeps going if your SSH connection drops:

```bash
tmux new -s setup
bin/setup.sh
```

If the connection drops, connect again and run `tmux attach -t setup` to see it.

The first run downloads Magento and the sample data and builds everything: about 20 to 40 minutes on a `t3.large`,
and up to an hour on a `t3.small`. At the end it prints the addresses and the admin password. **The password is
shown only once**: save it in your password manager.

## 9. Check HTTPS

Open `https://shop.example.com/` and `https://hyva.shop.example.com/` in your browser: they should load with a valid
certificate (and ask for the password protection user first, if you set it).

From your computer, you can also check the headers:

```bash
curl -sI https://shop.example.com/ | head -n 1             # 200, or 401 with password protection
curl -sI http://shop.example.com/ | grep -i '^location'     # redirects to https://
curl -sI https://shop.example.com/irios-sw.js | head -n 1   # 404 until push is set up, then 200
```

Behind Cloudflare, the first `curl` shows Cloudflare's headers (`server: cloudflare`), and the `http://` one
redirects with "Always Use HTTPS".

**Certificate renewal is automatic.** With `TLS_MODE=letsencrypt`, Caddy renews each certificate about a month before it expires, and keeps them
in the `caddy-data` volume. You only need to keep ports 80 and 443 open and the DNS records in place. If you want to
see it working: `docker compose logs caddy | grep -i certificate`.

## 10. Updates

Connect to the server, go to the repository folder and use `bin/update.sh` ([Updating](../README.md#updating) in
the README):

```bash
cd ~/iriosmedia-magento-app
bin/update.sh module          # the IRIOS Media module
bin/update.sh magento 2.4.8-p6  # a Magento patch
bin/update.sh images          # MariaDB, OpenSearch, Valkey, nginx, Caddy and PHP fixes
```

Each update takes a backup first and keeps the store in maintenance mode while it runs: a few minutes on a
`t3.large`, 15 to 20 minutes on a `t3.small`. Run long ones in `tmux`, as in step 8.

**System updates.** Ubuntu installs security updates by itself (unattended upgrades). Now and then, apply the rest
and reboot; the store comes back by itself:

```bash
sudo apt-get update && sudo apt-get -y upgrade && sudo reboot
```

## 11. Backups

`bin/backup.sh` puts a backup in `backups/` on the server ([Backups and restore](../README.md#backups-and-restore)).
A backup on the same server does not survive the loss of the server, so copy the backups somewhere else too. You
have two options, and they work well together.

**Option 1: copy the backups to S3.** S3 is AWS's file storage.

1. Create a bucket: S3 → **Create bucket**, for example `my-magento-test-backups`, in the same region. Keep
   **Block all public access** on.
2. Give the server permission to write in it, without keys on the server: IAM → **Roles** → **Create role** →
   **AWS service**, **EC2** → create a policy with only this permission (change the bucket name):

   ```json
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Effect": "Allow",
       "Action": ["s3:PutObject", "s3:ListBucket"],
       "Resource": ["arn:aws:s3:::my-magento-test-backups", "arn:aws:s3:::my-magento-test-backups/*"]
     }]
   }
   ```

   Name the role, for example `magento-test-backups`. Then EC2 → the instance → **Actions → Security → Modify IAM
   role** → choose it → **Update IAM role**.
3. Install the AWS command line tool on the server:

   ```bash
   sudo snap install aws-cli --classic
   ```

4. Copy the backups:

   ```bash
   aws s3 sync ~/iriosmedia-magento-app/backups/ s3://my-magento-test-backups/backups/ --exclude '*.log'
   ```

5. To do it every night after the backup, add it to the crontab line of the README (`crontab -e`):

   ```cron
   0 2 * * * cd /home/ubuntu/iriosmedia-magento-app && mkdir -p backups && bin/backup.sh >> backups/backup.log 2>&1 && aws s3 sync backups/ s3://my-magento-test-backups/backups/ --exclude '*.log' >> backups/backup.log 2>&1 && find backups -mindepth 1 -maxdepth 1 -type d -mtime +14 -exec rm -rf {} +
   ```

   To delete old backups in S3 too, add a lifecycle rule to the bucket (S3 → the bucket → **Management → Create
   lifecycle rule** → expire current versions after, for example, 30 days).

**Option 2: snapshots of the whole disk.** EC2 → **Elastic Block Store → Lifecycle Manager** → **Create lifecycle
policy** → **EBS snapshot policy**, target the instance's volume (by a tag such as `Name=magento-test-store`), and set
a daily schedule with, for example, 7 snapshots kept. A snapshot copies the whole server, so you can restore it as
it was, but it is less handy for moving the store elsewhere.

## 12. Monitoring

A few checks go a long way:

- **The containers:** `docker compose ps` shows whether each one is running and healthy.
- **The logs:** `docker compose logs --since 1h php caddy`, and Magento's own in `var/log`:
  `docker compose exec php tail -n 50 var/log/exception.log`.
- **Disk and memory:** `df -h /` (keep it under 80 %) and `free -h`. Docker images pile up after updates;
  `docker image prune` removes the ones no longer used.
- **AWS status checks:** EC2 → the instance → **Status and alarms** → **Create alarm** for "Status check failed",
  with the action **Recover** (or **Reboot**), so AWS brings the server back on a hardware problem. Add an email
  notification so you know it happened.
- **CPU credits** (T3): in the instance's monitoring, `CPUCreditBalance` falling to zero means the instance is busier
  than its baseline. With Unlimited credits it keeps its speed (and AWS charges the extra); consider a bigger size.
- **From the outside:** any uptime service that checks `https://shop.example.com/` every few minutes. With password
  protection, have it expect a `401`, or check `https://shop.example.com/irios-sw.js` once push is set up (it is
  open, and answers `200`).

## 13. Resize the server later

You can change the instance type at any time without reinstalling: everything is on the disk, and the Elastic IP
keeps the address.

1. Make a backup (`bin/backup.sh`), just in case.
2. EC2 → **Instances** → select the instance → **Instance state → Stop instance**, and wait until it is "Stopped".
3. **Actions → Instance settings → Change instance type** → choose the new type → **Apply**.
4. **Instance state → Start instance**. The store starts by itself with Docker.
5. Adjust the memory settings in `.env` to the new size: the small profile values for 2 GB, or the defaults of
   `.env.example` for 8 GB. Then apply them:

   ```bash
   cd ~/iriosmedia-magento-app
   docker compose up -d
   ```

   `MEMORY_PROFILE` and `STATIC_JOBS` only change how the next update runs, so they need nothing else.

To grow the disk, EC2 → **Volumes** → the volume → **Modify** → the new size; then on the server run
`sudo growpart /dev/nvme0n1 1 && sudo resize2fs /dev/nvme0n1p1` (check the device names with `lsblk` first).

## 14. Costs

AWS charges for each of these, so check them in the [AWS Pricing Calculator](https://calculator.aws/) for your region:

- the instance, per hour while it runs (and the extra CPU credits, if an Unlimited instance stays above its
  baseline);
- the disk (EBS gp3), per GB per month, also while the instance is stopped;
- the public IPv4 address (the Elastic IP), per hour;
- outbound data transfer;
- snapshots and S3 storage for backups.

A test store that nobody uses at night or on weekends can be stopped then (step 13, steps 2 and 4): you stop paying
for the instance, though the disk and the IP address still count.

## 15. Behind Cloudflare

Use this when the domains are in Cloudflare and you want its proxy in front of the store (the orange cloud): Cloudflare
then serves HTTPS to shoppers with its own certificate, hides the server's address and absorbs unwanted traffic. With
SSL/TLS mode **Flexible**, Cloudflare talks to the server over plain HTTP, so the server needs no certificate.

How the store handles it (`TLS_MODE=cloudflare-flexible`, `docker/caddy/cloudflare-flexible.Caddyfile`):

- Caddy listens only on port 80, with automatic HTTPS off.
- It trusts Cloudflare's address ranges as a proxy and takes the shopper's IP address from the `CF-Connecting-IP`
  header that Cloudflare adds.
- It tells nginx and Magento that the request was HTTPS (`X-Forwarded-Proto: https`). Magento keeps `https://`
  base URLs, with "Use Secure URLs" on for the storefront and the admin, and reads that header
  (`web/secure/offloader_header` = `X-Forwarded-Proto`), so it never redirects to HTTPS in a loop. `bin/setup.sh`
  sets all of this.
- Password protection works as before, with `/rest/*` still open for the IRIOS Media sync service.
- Push notifications work: shoppers reach the store over HTTPS, which is what browsers need.

**Flexible or Full (strict).** With Flexible, the stretch between Cloudflare and the server is not encrypted; it
crosses the internet as plain HTTP. That is acceptable for a test store with test data. The encrypted alternative is
SSL/TLS mode **Full (strict)** with a **Cloudflare Origin Certificate**: a free certificate from Cloudflare (SSL/TLS →
Origin Server → Create Certificate), installed on the server, that only Cloudflare trusts. Caddy would then serve port
443 with that certificate (`tls /path/cert.pem /path/key.pem` in a Caddyfile) and the security group would open 443
to Cloudflare instead of 80. This repository does not set that up for you; it is optional.

### What changes in the steps above

**Step 2, security group.** Open HTTP only to Cloudflare, so nobody can reach the server around it:

| Type | Port | Source |
|---|---|---|
| SSH | 22 | My IP |
| HTTP | 80 | Each of Cloudflare's IPv4 and IPv6 ranges, one rule per range |

HTTPS (443) is not needed in this mode. (With `TLS_MODE=letsencrypt` behind Cloudflare's DNS only, the usual rules of
step 2 apply instead.)

Cloudflare publishes its ranges at https://www.cloudflare.com/ips/. To see the list, and to update the copy Caddy
uses, run on the server:

```bash
bin/cloudflare-ips.sh
docker compose restart caddy
```

The ranges change rarely. Check the page every few months, or when Cloudflare announces a change, and update both
the security group and Caddy's copy. A handy way to keep the security group tidy is a **managed prefix list**
(VPC → **Managed prefix lists** → **Create prefix list**, one for IPv4 and one for IPv6, with Cloudflare's ranges),
used as the source of the HTTP rule: you then update the list, not every rule.

Docker publishes Caddy's ports outside of the server's own firewall (ufw), so the security group is the place to
restrict them.

**Step 4, DNS.** In Cloudflare → your domain → **DNS → Records**, create an **A** record for each store view domain
with the Elastic IP as its value and **Proxy status: Proxied** (orange cloud).

**Step 7, `.env`.** Set:

```dotenv
TLS_MODE=cloudflare-flexible
```

`ACME_EMAIL` is not used. If the store was already installed with another mode, run `bin/setup.sh` again: it updates
the base URLs and the secure settings.

### Cloudflare settings

In the Cloudflare dashboard, for your domain:

1. **SSL/TLS → Overview**: encryption mode **Flexible**.
2. **SSL/TLS → Edge Certificates**: **Always Use HTTPS** on, so shoppers who type `http://` go to `https://` at
   Cloudflare, before reaching the server.
3. **Speed → Optimization → Content Optimization**: **Rocket Loader** off. Rocket Loader rewrites and delays the
   page's JavaScript, which breaks Magento's scripts and the IRIOS Media ones (consent, events and ads).
4. **Caching**: leave the defaults. Cloudflare does not cache HTML pages by default, which is what Magento needs
   (pages differ per shopper, cart and consent). Keep it that way: rules such as "Cache Everything" would serve one
   shopper's page to another.
5. **Scrape Shield → Email Address Obfuscation**: not needed; you can turn it off, so Cloudflare leaves the HTML as
   Magento sends it.

Then check, from your computer:

```bash
curl -sI https://shop.example.com/ | grep -i '^server'             # server: cloudflare
curl -sI https://shop.example.com/irios-sw.js | head -n 1          # 200 once push is set up, no redirect
```
