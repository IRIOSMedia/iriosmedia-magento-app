#!/usr/bin/env bash
# Rewrites docker/caddy/cloudflare-ips.caddy with Cloudflare's current proxy address ranges, and prints them, one per
# line, for the server's firewall (the AWS security group, see "Behind Cloudflare" in docs/aws.md).
# Only needed with TLS_MODE=cloudflare-flexible. Then restart Caddy: docker compose restart caddy
#   bin/cloudflare-ips.sh
set -euo pipefail
cd "$(dirname "$0")/.."

v4="$(curl -fsS https://www.cloudflare.com/ips-v4)"
v6="$(curl -fsS https://www.cloudflare.com/ips-v6)"
ranges="$(printf '%s\n%s\n' "$v4" "$v6" | grep -E '^[0-9a-fA-F:.]+/[0-9]+$')"
[[ $(wc -l <<<"$ranges") -ge 10 ]] || { echo "Unexpected answer from cloudflare.com: nothing changed." >&2; exit 1; }

file=docker/caddy/cloudflare-ips.caddy
{
    sed -n '/^#/p' "$file"
    printf 'trusted_proxies static %s\n' "$(tr '\n' ' ' <<<"$ranges" | sed 's/ $//')"
} > "$file.new"
mv "$file.new" "$file"

echo "Updated $file. Cloudflare's ranges:"
echo "$ranges"
