#!/bin/bash

set -e

echo "===================================="
echo "  CLOUDFLARE UFW DUAL-STACK FIX    "
echo "===================================="

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo)"
  exit 1
fi

# 1. Cleanup: Remove any existing rules with the 'Cloudflare IP' comment
# This clears the deck so we don't have to worry about "Position 1" errors
echo "Cleaning up old Cloudflare rules..."
# Delete IPv6 first
while ufw status numbered | grep '(v6)' | grep -q 'Cloudflare IP'; do
    NUM=$(ufw status numbered | grep '(v6)' | grep 'Cloudflare IP' | awk -F"[][]" '{print $2}' | head -n1)
    ufw --force delete $NUM
done
# Delete IPv4
while ufw status numbered | grep -q 'Cloudflare IP'; do
    NUM=$(ufw status numbered | grep 'Cloudflare IP' | awk -F"[][]" '{print $2}' | head -n1)
    ufw --force delete $NUM
done

# 2. Fetch latest Cloudflare IPs
echo "Fetching latest IPv4 and IPv6 ranges..."
CF_IPV4=$(curl -s https://www.cloudflare.com/ips-v4)
CF_IPV6=$(curl -s https://www.cloudflare.com/ips-v6)

# 3. Allow SSH
ufw allow ssh

# 4. Whitelist Cloudflare IPv4
for ip in $CF_IPV4; do
    echo "Whitelisting IPv4: $ip"
    # Using 'allow' puts them in the correct order for Cloudflare traffic
    ufw allow from "$ip" to any port 80,443 proto tcp comment 'Cloudflare IP'
done

# 5. Whitelist Cloudflare IPv6
for ip in $CF_IPV6; do
    echo "Whitelisting IPv6: $ip"
    ufw allow from "$ip" to any port 80,443 proto tcp comment 'Cloudflare IP'
done

# 6. Finalize
ufw --force enable

echo "===================================="
echo " Cloudflare Update Complete        "
echo "===================================="
ufw status numbered