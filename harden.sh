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

# 5. Configure UFW Action
cat > /etc/fail2ban/action.d/ufw.conf <<'EOF'
[Definition]
actionban = /usr/sbin/ufw insert 1 deny from <ip> to any
actionunban = /usr/sbin/ufw delete deny from <ip> to any
EOF

# 6. Create Filters
echo "Creating Fail2Ban filters..."
echo "Configuring Probing Filters..."
cat > /etc/fail2ban/filter.d/nginx-403.conf <<'EOF'
[Definition]
failregex = ^<HOST> -.*"(GET|POST|HEAD).*" 403
EOF

echo "Configuring Honeypot Filters..."
cat > /etc/fail2ban/filter.d/nginx-honeypot.conf <<'EOF'
[Definition]
failregex = ^<HOST> -.*"(GET|POST|HEAD).*" 403
EOF

echo "Configuring Scanner Filters..."
cat > /etc/fail2ban/filter.d/nginx-scanner.conf <<'EOF'
[Definition]
failregex = ^<HOST> .* "(GET|POST|HEAD).*(\.env|\.git/config|phpinfo\.php|\.aws|\.DS_Store|vendor/phpunit|composer\.json)
EOF

echo "Configuring Sensetive Files Filters..."
cat > /etc/fail2ban/filter.d/nginx-sensitive-files.conf <<'EOF'
[Definition]
failregex = ^<HOST> .* "(GET|POST|HEAD).*\\.(env|git|aws|DS_Store|bak|sql)
EOF

echo "Configuring AI Scrapper Filters..."
cat > /etc/fail2ban/filter.d/nginx-ai-scrapers.conf <<'EOF'
[Definition]
failregex = ^<HOST> .* "(GET|POST|HEAD).*" .*"(GPTBot|ChatGPT|ClaudeBot|Amazonbot|CCBot|anthropic-ai)"
EOF

echo "Configuring Exploit Filters..."
cat <<EOF > /etc/fail2ban/filter.d/nginx-exploits.conf
[Definition]
failregex = ^<HOST> -.*"(GET|POST|HEAD).*(union|select|insert|update|delete|drop|concat|information_schema|benchmark).*"
            ^<HOST> -.*"(GET|POST|HEAD).*(<|%3C)script.*(>|%3E).*"
            ^<HOST> -.*"(GET|POST|HEAD).*(onload|onerror|alert|document\.cookie).*"
            ^<HOST> -.*"(GET|POST|HEAD).*\.\./\.\./.*"
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
banaction = ufw
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

[nginx-scanners]
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
ufw allow ssh
for ip in $CF_IPV4 $CF_IPV6; do
    ufw allow from "$ip" to any port 80,443 proto tcp comment 'Cloudflare IP'
done
ufw --force enable

systemctl restart fail2ban
echo "Done."