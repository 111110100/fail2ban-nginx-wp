#!/bin/bash

set -e

# --- CONFIGURATION (FILL THESE IN) ---
CF_ACCOUNT_ID=""
CF_API_TOKEN=""
MY_IP="" # Your home IP to prevent self-lockout
# -------------------------------------

echo "===================================="
echo " MASTER NGINX + CF SECURITY SETUP "
echo "===================================="

# 1. Root Check
if [ "$EUID" -ne 0 ]; then
  echo "Error: Please run as root (sudo)"
  exit 1
fi

# 2. Cloudflare Variable Check
if [[ -z "$CF_ACCOUNT_ID" || -z "$CF_API_TOKEN" ]]; then
  echo "Error: CF_ACCOUNT_ID or CF_API_TOKEN is blank."
  echo "Please edit the script and add your Cloudflare credentials."
  exit 1
fi

# 3. Intelligent Package Installation
is_installed() {
    dpkg -s "$1" >/dev/null 2>&1
}

PACKAGES=("nginx" "fail2ban" "ufw" "jq" "curl")
TO_INSTALL=()

for pkg in "${PACKAGES[@]}"; do
    if is_installed "$pkg"; then
        echo "[SKIP] $pkg is already installed."
    else
        echo "[MARK] $pkg needs to be installed."
        TO_INSTALL+=("$pkg")
    fi
done

if [ ${#TO_INSTALL[@]} -ne 0 ]; then
    echo "Installing missing packages: ${TO_INSTALL[*]}..."
    apt update
    apt install -y "${TO_INSTALL[@]}"
fi

# 4. Configure Cloudflare API Action
cat > /etc/fail2ban/action.d/cloudflare.conf <<'EOF'
[Definition]
actionban = curl -s -X POST "https://api.cloudflare.com/client/v4/accounts/<cfaccount>/firewall/access_rules/rules" \
            -H "Authorization: Bearer <cftoken>" \
            -H "Content-Type: application/json" \
            --data '{"mode":"block","configuration":{"target":"ip","value":"<ip>"},"notes":"Fail2Ban Global: <jailname>"}'

actionunban = id=$(curl -s -X GET "https://api.cloudflare.com/client/v4/accounts/<cfaccount>/firewall/access_rules/rules?configuration.target=ip&configuration.value=<ip>&mode=block" \
              -H "Authorization: Bearer <cftoken>" \
              -H "Content-Type: application/json" | jq -r '.result[0].id'); \
              if [ "$id" != "null" ] && [ "$id" != "" ]; then curl -s -X DELETE "https://api.cloudflare.com/client/v4/accounts/<cfaccount>/firewall/access_rules/rules/$id" \
              -H "Authorization: Bearer <cftoken>" \
              -H "Content-Type: application/json"; fi
[Init]
cftoken = 
cfaccount = 
EOF

# 4b. Configure WP-Cron Action
cat > /etc/fail2ban/action.d/nginx-wp-cron-action.conf <<'EOF'
[Definition]
actionban = echo "[$(date)] <jailname> BAN: <ip> (Abusing wp-cron.php)" >> /var/log/fail2ban-wp-cron.log
actionunban = echo "[$(date)] <jailname> UNBAN: <ip>" >> /var/log/fail2ban-wp-cron.log
EOF

# 5. Configure UFW Action (Fixed for IPv6 and Empty Rulesets)
cat > /etc/fail2ban/action.d/ufw.conf <<'EOF'
[Definition]
actionban = /usr/sbin/ufw insert 1 deny from <ip>
actionunban = /usr/sbin/ufw delete deny from <ip>
EOF

# 6. Create Filters
echo "Creating Fail2Ban filters..."
echo "Configuring Probing Filters..."
cat > /etc/fail2ban/filter.d/nginx-403.conf <<'EOF'
[Definition]
failregex = ^<HOST> -.*"(GET|POST|HEAD) /.* HTTP/.*" 403
EOF

echo "Configuring Honeypot Filters..."
cat > /etc/fail2ban/filter.d/nginx-honeypot.conf <<'EOF'
[Definition]
failregex = ^<HOST> -.*"(GET|POST|HEAD) /.* HTTP/.*" 403
EOF

echo "Configuring Scanner Filters..."
cat > /etc/fail2ban/filter.d/nginx-scanner.conf <<'EOF'
[Definition]
failregex = ^<HOST> -.*"(GET|POST|HEAD) /.*(\.env|\.git|\.aws|\.DS_Store|phpinfo\.php|composer\.json|vendor/phpunit|wp-admin/install\.php) HTTP/.*" (403|404)
EOF

echo "Configuring Sensitive Files Filters..."
cat > /etc/fail2ban/filter.d/nginx-sensitive-files.conf <<'EOF'
[Definition]
failregex = ^<HOST> -.*"(GET|POST|HEAD) /.*\.(env|git|aws|bak|sql|phpinfo|htaccess|config|log|backup|old|swp) HTTP/.*" (404|403|401)
EOF

echo "Configuring AI Scraper Filters..."
cat > /etc/fail2ban/filter.d/nginx-ai-scrapers.conf <<'EOF'
[Definition]
failregex = ^<HOST> -.*"(GET|POST|HEAD) /.* HTTP/.*" .*"(GPTBot|ChatGPT|ClaudeBot|Amazonbot|CCBot|anthropic-ai|Bytespider|ImagesiftBot)"
EOF

echo "Configuring WordPress Login Filters..."
cat > /etc/fail2ban/filter.d/nginx-wp-login.conf <<'EOF'
[Definition]
failregex = ^<HOST> -.*"POST /wp-login\.php HTTP/.*" 200
EOF

echo "Configuring WordPress WP-Cron Filters..."
cat > /etc/fail2ban/filter.d/nginx-wp-cron.conf <<'EOF'
[Definition]
# Target wp-cron calls, especially those resulting in timeouts (504) or high frequency
failregex = ^<HOST> -.*"(GET|POST) /wp-cron\.php(?:\?.*)? HTTP/.*" (?:504|200|499)
EOF

echo "Configuring Exploit Filters..."
cat <<'EOF' > /etc/fail2ban/filter.d/nginx-exploits.conf
[Definition]
failregex = ^<HOST> -.*"(GET|POST|HEAD) .*\b(union|select|insert|update|delete|drop|concat|information_schema|benchmark)\b.*"
            ^<HOST> -.*"(GET|POST|HEAD) .*(\<|%%3C)script.*(\>|%%3E).*"
            ^<HOST> -.*"(GET|POST|HEAD) .*(onload|onerror|alert|document\.cookie).*"
            ^<HOST> -.*"(GET|POST|HEAD) .*\.\.\/\.\.\/.*"
EOF

# 7. Global Jail Configuration
echo "Configuring jail.local..."
CF_IPV4=$(curl -s https://www.cloudflare.com/ips-v4)
CF_IPV6=$(curl -s https://www.cloudflare.com/ips-v6)
IGNORE_LIST=$(echo "$CF_IPV4 $CF_IPV6" | tr '\n' ' ')

cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
cf_token = $CF_API_TOKEN
cf_account = $CF_ACCOUNT_ID
ignoreip = 127.0.0.1/8 ::1 $MY_IP $IGNORE_LIST
bantime = 3600
findtime = 600
maxretry = 5
action = ufw
         cloudflare[cftoken="$CF_API_TOKEN", cfaccount="$CF_ACCOUNT_ID"]

[nginx-403]
enabled = true
port = http,https
filter = nginx-403
logpath = /var/log/nginx/*access.log
maxretry = 10

[nginx-honeypot]
enabled = true
filter = nginx-honeypot
logpath = /var/log/nginx/honeypot.log
maxretry = 1
bantime = 86400

[nginx-scanner]
enabled = true
filter = nginx-scanner
logpath = /var/log/nginx/*access.log
maxretry = 1
bantime = 86400

[nginx-sensitive-files]
enabled = true
filter = nginx-sensitive-files
logpath = /var/log/nginx/*access.log
maxretry = 1
bantime = 86400

[nginx-ai-scrapers]
enabled = true
filter = nginx-ai-scrapers
logpath = /var/log/nginx/*access.log
maxretry = 2
bantime = 86400

[nginx-wp-login]
enabled = true
port = http,https
filter = nginx-wp-login
logpath = /var/log/nginx/*access.log
maxretry = 3
findtime = 3600
bantime = 86400

[nginx-wp-cron]
enabled = true
port = http,https
filter = nginx-wp-cron
logpath = /var/log/nginx/*access.log
maxretry = 5
findtime = 600
bantime = 86400
action = ufw
         cloudflare[cftoken="$CF_API_TOKEN", cfaccount="$CF_ACCOUNT_ID"]
         nginx-wp-cron-action

[recidive]
enabled = true
logpath = /var/log/fail2ban.log
bantime = 604800
findtime = 86400
maxretry = 5

[nginx-exploits]
enabled = true
port = http,https
filter = nginx-exploits
logpath = /var/log/nginx/*access.log
maxretry = 2
findtime = 3600
bantime = 86400
EOF

# 8. UFW Whitelisting
echo "Applying UFW whitelists..."
# Ensure IPv6 is enabled in UFW
sed -i 's/IPV6=no/IPV6=yes/g' /etc/default/ufw 2>/dev/null || true

# Fetch Cloudflare IPs with fallbacks
CF_IPV4=$(curl -s https://www.cloudflare.com/ips-v4 || echo "173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22 141.101.64.0/18 108.162.192.0/18 190.93.240.0/20 188.114.96.0/20 197.234.240.0/22 198.41.128.0/17 162.158.0.0/15 104.16.0.0/13 104.24.0.0/14 172.64.0.0/13 131.0.72.0/22")
CF_IPV6=$(curl -s https://www.cloudflare.com/ips-v6 || echo "2400:cb00::/32 2606:4700::/32 2803:f800::/32 2405:b500::/32 2405:8100::/32 2a06:98c0::/29 2c0f:f248::/32")

# Basic system rules
ufw allow ssh

# Add Cloudflare Allow Rules (Ensures ruleset isn't empty)
for ip in $CF_IPV4 $CF_IPV6; do
    ufw allow from "$ip" to any port 80,443 proto tcp comment 'Cloudflare IP'
done

# Force enable UFW
echo "y" | ufw enable
ufw reload

systemctl restart fail2ban
echo "Done."

# 9. Final Validation
echo ""
echo "------------------------------------------------"
echo "🏁 INSTALLATION COMPLETE"
echo "------------------------------------------------"
echo "Running automated sanity check on filters..."

# Make sure the check script is executable
chmod +x ./fail2ban-test.sh

# Run the check
./fail2ban-test.sh

echo ""
echo "Verify your active bans with: ./cf-manage.sh list"
echo "Test your edge defense with: ./fail2ban-cf-test.sh <URL> all"
echo "------------------------------------------------"