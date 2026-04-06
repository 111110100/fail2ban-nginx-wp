#!/bin/bash

set -euo pipefail

# --- CONFIGURATION ---
# Load from .env file if it exists, otherwise use defaults
ENV_FILE="$(dirname "$0")/.env"
if [[ -f "$ENV_FILE" ]]; then
    # shellcheck source=.env
    source "$ENV_FILE"
fi

CF_ACCOUNT_ID="${CF_ACCOUNT_ID:-}"
CF_API_TOKEN="${CF_API_TOKEN:-}"
MY_IP="${MY_IP:-}"
# ---------------------

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
# Only match honeypot-specific paths that real users should never access
failregex = ^<HOST> -.*"(GET|POST|HEAD) /(\.env|\.git|wp-admin/install\.php|phpinfo\.php|vendor/phpunit|composer\.json) HTTP/.*" 403
ignoreregex =
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
# Match POST logins (200) and repeated GET admin attempts (302)
failregex = ^<HOST> -.*"POST /wp-login\.php HTTP/.*" 200
            ^<HOST> -.*"GET /wp-admin/index\.php HTTP/.*" 302
EOF

echo "Configuring WordPress WP-Cron Filters..."
cat > /etc/fail2ban/filter.d/nginx-wp-cron.conf <<'EOF'
[Definition]
# Target wp-cron calls, especially those resulting in timeouts (504) or high frequency
failregex = ^<HOST> -.*"(GET|POST) /wp-cron\.php(?:\?.*)? HTTP/.*" (?:504|200|499)
EOF

echo "Configuring PHP Probe Filters..."
cat > /etc/fail2ban/filter.d/nginx-php-probes.conf <<'EOF'
[Definition]
# Target random PHP files, shells, and admin tools that shouldn't exist
failregex = ^<HOST> -.*"(GET|POST|HEAD) /.*\.(php|phtml|php3|php4|php5|phps) HTTP/.*" 404
EOF

echo "Configuring XML-RPC Filters..."
cat > /etc/fail2ban/filter.d/nginx-xmlrpc.conf <<'EOF'
[Definition]
# Target XML-RPC flooding (even with double slashes)
failregex = ^<HOST> -.*"POST /+xmlrpc\.php HTTP/.*" 200
EOF

echo "Configuring Recidive Filter..."
cat > /etc/fail2ban/filter.d/recidive.conf <<'EOF'
[Definition]
# Match ban notices from all jails except recidive itself (prevents recursion)
failregex = ^\s*(?:\S+ )?(?:fail2ban\.actions\s*:?\s*)?NOTICE\s+\[(?!recidive\]).+\]\s+Ban\s+<HOST>\s*$
ignoreregex =
EOF

echo "Configuring Exploit Filters..."
cat <<'EOF' > /etc/fail2ban/filter.d/nginx-exploits.conf
[Definition]
# Target SQL injection attempts in query strings only (avoids false positives on legitimate content)
failregex = ^<HOST> -.*"(GET|POST|HEAD) /[^\"]*\?.*(union\s+(all\s+)?select|select\s+.*\bfrom\b|information_schema|benchmark\s*\(|load_file\s*\()
            # Target XSS attempts
            ^<HOST> -.*"(GET|POST|HEAD) [^\"]*(%3C|<)script[^\"]*(%3E|>).*"
            # Target path traversal
            ^<HOST> -.*"(GET|POST|HEAD) [^\"]*\.\./\.\./.*"
ignoreregex =
EOF

echo "Configuring WordPress REST API Filters..."
cat > /etc/fail2ban/filter.d/nginx-wp-rest.conf <<'EOF'
[Definition]
# Target user enumeration and REST API abuse
failregex = ^<HOST> -.*"(GET|POST) /wp-json/wp/v2/users HTTP/.*" 200
            ^<HOST> -.*"(GET|POST) /wp-json/yoast HTTP/.*" 200
ignoreregex =
EOF

# 6b. Create Nginx Snippets
echo "Creating Nginx snippets..."

# Fetch Cloudflare IPs for the snippet
CF_IPV4=$(curl -s https://www.cloudflare.com/ips-v4 || echo "# Failed to fetch IPv4")
CF_IPV6=$(curl -s https://www.cloudflare.com/ips-v6 || echo "# Failed to fetch IPv6")

# Ensure snippets directory exists
mkdir -p /etc/nginx/snippets

cat > /etc/nginx/snippets/cloudflare-ips.conf <<'CFEOF'
# ==============================================================================
# CLOUDFLARE REAL IP CONFIGURATION
# Auto-generated by harden.sh - Do not edit manually
# ==============================================================================
# This file tells Nginx to trust the CF-Connecting-IP header from Cloudflare
# and whitelist all Cloudflare proxy IP ranges for real_ip resolution.
#
# Include this in your server {} block:
#   include snippets/cloudflare-ips.conf;
# ==============================================================================

# Trust the header provided by Cloudflare
real_ip_header CF-Connecting-IP;

# IPv4 ranges
CFEOF

# Append IPv4 ranges
for ip in $CF_IPV4; do
    echo "set_real_ip_from $ip;" >> /etc/nginx/snippets/cloudflare-ips.conf
done

cat >> /etc/nginx/snippets/cloudflare-ips.conf <<'CFEOF'

# IPv6 ranges
CFEOF

# Append IPv6 ranges
for ip in $CF_IPV6; do
    echo "set_real_ip_from $ip;" >> /etc/nginx/snippets/cloudflare-ips.conf
done

cat >> /etc/nginx/snippets/cloudflare-ips.conf <<'CFEOF'

# Mark the resolved IP as trusted (prevents double-proxy issues)
# real_ip_recursive on; # Uncomment if behind multiple proxy layers
CFEOF

echo "Created /etc/nginx/snippets/cloudflare-ips.conf"

# 7. Global Jail Configuration
echo "Configuring jail.local..."
IGNORE_LIST=$(echo "$CF_IPV4 $CF_IPV6" | tr '\n' ' ')

cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
cf_token = $CF_API_TOKEN
cf_account = $CF_ACCOUNT_ID
ignoreip = 127.0.0.1/8 ::1 $MY_IP $IGNORE_LIST
bantime = 3600
findtime = 600
maxretry = 5
# Robust action definition using Fail2Ban interpolation
banaction = ufw
            cloudflare[cftoken="$CF_API_TOKEN", cfaccount="$CF_ACCOUNT_ID"]
action = %(action_mw)s

[nginx-403]
enabled = true
port = http,https
filter = nginx-403
logpath = /var/log/nginx/*access*log
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
logpath = /var/log/nginx/*access*log
maxretry = 1
bantime = 86400

[nginx-sensitive-files]
enabled = true
filter = nginx-sensitive-files
logpath = /var/log/nginx/*access*log
maxretry = 1
bantime = 86400

[nginx-ai-scrapers]
enabled = true
filter = nginx-ai-scrapers
logpath = /var/log/nginx/*access*log
maxretry = 2
bantime = 86400

[nginx-wp-login]
enabled = true
port = http,https
filter = nginx-wp-login
logpath = /var/log/nginx/*access*log
maxretry = 3
findtime = 3600
bantime = 86400

[nginx-wp-cron]
enabled = true
port = http,https
filter = nginx-wp-cron
logpath = /var/log/nginx/*access*log
maxretry = 5
findtime = 600
bantime = 86400
action = %(action_mw)s
         nginx-wp-cron-action

[nginx-php-probes]
enabled = true
port = http,https
filter = nginx-php-probes
logpath = /var/log/nginx/*access*log
maxretry = 2
findtime = 600
bantime = 86400

[nginx-xmlrpc]
enabled = true
port = http,https
filter = nginx-xmlrpc
logpath = /var/log/nginx/*access*log
maxretry = 3
findtime = 600
bantime = 86400

[recidive]
enabled = true
filter = recidive
logpath = /var/log/fail2ban.log
bantime = 604800
findtime = 86400
maxretry = 5
action = ufw[name=%(__name__)s, port="%(port)s", protocol="%(protocol)s", chain="%(chain)s"]
         cloudflare[cftoken="$CF_API_TOKEN", cfaccount="$CF_ACCOUNT_ID"]

[nginx-exploits]
enabled = true
port = http,https
filter = nginx-exploits
logpath = /var/log/nginx/*access*log
maxretry = 2
findtime = 3600
bantime = 86400

[nginx-wp-rest]
enabled = true
port = http,https
filter = nginx-wp-rest
logpath = /var/log/nginx/*access*log
maxretry = 3
findtime = 600
bantime = 86400
EOF

# 8. UFW Whitelisting
echo "Applying UFW whitelists..."
# Ensure IPv6 is enabled in UFW
sed -i 's/IPV6=no/IPV6=yes/g' /etc/default/ufw 2>/dev/null || true

# Basic system rules
ufw allow ssh || { echo "ERROR: Failed to allow SSH"; exit 1; }

# Add Cloudflare Allow Rules with idempotency check (prevents duplicates on re-run)
CF_ALLOW_COUNT=$(ufw status numbered 2>/dev/null | grep -c "Cloudflare IP" || true)
if [ "$CF_ALLOW_COUNT" -eq 0 ]; then
    echo "Adding Cloudflare IP allow rules..."
    for ip in $CF_IPV4 $CF_IPV6; do
        ufw allow from "$ip" to any port 80,443 proto tcp comment 'Cloudflare IP' || echo "WARNING: Failed to add rule for $ip"
    done
else
    echo "Cloudflare IP allow rules already exist ($CF_ALLOW_COUNT rules), skipping."
fi

# Force enable UFW
echo "y" | ufw enable || { echo "ERROR: Failed to enable UFW"; exit 1; }
ufw reload || { echo "ERROR: Failed to reload UFW"; exit 1; }

systemctl restart fail2ban || { echo "ERROR: Failed to restart Fail2Ban"; exit 1; }
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
echo "Run a health check with: ./healthcheck.sh"
echo "------------------------------------------------"