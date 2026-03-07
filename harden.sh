#!/bin/bash

set -e

echo "===================================="
echo " NGINX + FAIL2BAN HARDENING SCRIPT "
echo "===================================="

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo)"
  exit 1
fi

# Helper function to check if package is installed
is_installed() {
    dpkg -s "$1" >/dev/null 2>&1
}

BACKUP_DIR="/root/server-security-backup-$(date +%s)"
mkdir -p "$BACKUP_DIR"

echo "Backup directory: $BACKUP_DIR"

backup_file() {
    if [ -f "$1" ]; then
        cp "$1" "$BACKUP_DIR/"
    fi
}

########################################
# INSTALLATION CHECK
########################################

PACKAGES=("fail2ban" "ufw" "nginx" "curl")
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

systemctl enable nginx
systemctl enable fail2ban

########################################
# UFW CONFIGURATION
########################################

echo "Configuring firewall..."
ufw allow ssh
ufw allow 'Nginx Full'
ufw --force enable

########################################
# FIX FAIL2BAN UFW ACTION (The "Error Banning" Fix)
########################################

echo "Updating Fail2Ban UFW action syntax..."
# This avoids the "cannot open HOST" and "Bad source address" errors
cat > /etc/fail2ban/action.d/ufw.conf <<'EOF'
[Definition]
actionstart = 
actionstop = 
actioncheck = 
actionban = /usr/sbin/ufw insert 1 deny from <ip> to any
actionunban = /usr/sbin/ufw delete deny from <ip> to any
EOF

########################################
# CREATE NGINX HONEYPOT LOG
########################################

echo "Creating honeypot log..."
touch /var/log/nginx/honeypot.log
chmod 644 /var/log/nginx/honeypot.log
chown www-data:adm /var/log/nginx/honeypot.log

########################################
# ADD NGINX SECURITY BLOCK
########################################

echo "Adding nginx scanner traps..."
NGINX_CONF="/etc/nginx/snippets/security-traps.conf"
backup_file $NGINX_CONF

cat > $NGINX_CONF <<'EOF'
# Scanner trap endpoints
location ~* (\.env|\.git|\.aws|\.DS_Store|phpinfo\.php|composer\.json|vendor/phpunit|wp-admin/install\.php) {
    access_log /var/log/nginx/honeypot.log;
    return 403;
}

# Tarpit scanners
location ~* (\.sql|\.bak|\.backup|\.old|\.tar|\.zip) {
    limit_rate 1k;
    return 403;
}
EOF

########################################
# FAIL2BAN FILTERS
########################################

echo "Creating Fail2Ban filters..."

cat > /etc/fail2ban/filter.d/nginx-403.conf <<'EOF'
[Definition]
failregex = ^<HOST> -.*"(GET|POST|HEAD).*" 403
ignoreregex =
EOF

cat > /etc/fail2ban/filter.d/nginx-honeypot.conf <<'EOF'
[Definition]
failregex = ^<HOST> -.*"(GET|POST|HEAD).*" 403
ignoreregex =
EOF

cat > /etc/fail2ban/filter.d/nginx-scanner.conf <<'EOF'
[Definition]
failregex = ^<HOST> .* "(GET|POST|HEAD).*(\.env|\.git/config|phpinfo\.php|\.aws|\.DS_Store|vendor/phpunit|composer\.json)
ignoreregex =
EOF

cat > /etc/fail2ban/filter.d/nginx-sensitive-files.conf <<'EOF'
[Definition]
failregex = ^<HOST> .* "(GET|POST|HEAD).*\\.(env|git|aws|DS_Store|bak|sql)
ignoreregex =
EOF

cat > /etc/fail2ban/filter.d/nginx-ai-scrapers.conf <<'EOF'
[Definition]
failregex = ^<HOST> .* "(GET|POST|HEAD).*" .*"(GPTBot|ChatGPT|ClaudeBot|Amazonbot|CCBot|anthropic-ai)"
ignoreregex =
EOF

########################################
# FAIL2BAN JAIL CONFIG
########################################

echo "Creating Fail2Ban jail configuration..."
backup_file /etc/fail2ban/jail.local

cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1
bantime = 3600
findtime = 600
maxretry = 5
backend = auto
banaction = ufw

[nginx-403]
enabled = true
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
EOF

########################################
# VALIDATE & RESTART
########################################

echo "Testing nginx configuration..."
nginx -t

echo "Restarting services..."
systemctl restart nginx
systemctl restart fail2ban

echo "Waiting for Fail2Ban to initialize..."
for i in {1..15}; do
    if fail2ban-client ping >/dev/null 2>&1; then
        echo "Fail2Ban is ready!"
        break
    fi
    sleep 1
done

echo "===================================="
echo " SECURITY INSTALLATION COMPLETE "
echo "===================================="
ufw status numbered
fail2ban-client status