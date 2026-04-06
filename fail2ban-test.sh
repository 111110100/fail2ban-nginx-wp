#!/bin/bash

set -euo pipefail

# --- COLORS FOR OUTPUT ---
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "------------------------------------------------"
echo "🔍 FAIL2BAN REGEX SANITY CHECK"
echo "------------------------------------------------"

check_filter() {
    local FILTER_NAME=$1
    local LOG_LINE=$2
    local FILTER_PATH="/etc/fail2ban/filter.d/$FILTER_NAME.conf"

    echo -n "Testing $FILTER_NAME... "

    if [ ! -f "$FILTER_PATH" ]; then
        echo -e "${RED}FAILED (Filter file not found)${NC}"
        return
    fi

    # Try to match the log line against the filter
    # Note: In a real environment, fail2ban-regex would be used.
    # For this script's sanity check within the repo, we assume it will be run on a system with fail2ban installed.
    if command -v fail2ban-regex &> /dev/null; then
        fail2ban-regex "$LOG_LINE" "$FILTER_PATH" > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}PASSED${NC}"
        else
            echo -e "${RED}FAILED (No Match)${NC}"
            fail2ban-regex "$LOG_LINE" "$FILTER_PATH"
        fi
    else
        echo -e "${RED}SKIPPED (fail2ban-regex not found)${NC}"
    fi
}

# --- DEFINE TEST CASES ---

# 1. Nginx 403 (Forbidden Access Spikes)
check_filter "nginx-403" '1.2.3.4 - - [10/Mar/2026:20:00:01 +1100] "GET /phpmyadmin HTTP/1.1" 403 150'

# 2. Nginx Honeypot (now targets specific paths only)
check_filter "nginx-honeypot" '1.2.3.4 - - [10/Mar/2026:20:00:01 +1100] "GET /.env HTTP/1.1" 403 150'
check_filter "nginx-honeypot" '1.2.3.4 - - [10/Mar/2026:20:00:01 +1100] "GET /.git HTTP/1.1" 403 150'
check_filter "nginx-honeypot" '1.2.3.4 - - [10/Mar/2026:20:00:01 +1100] "GET /wp-admin/install.php HTTP/1.1" 403 150'

# 3. Nginx Scanner
check_filter "nginx-scanner" '1.2.3.4 - - [10/Mar/2026:20:00:01 +1100] "GET /.env HTTP/1.1" 403 150'
check_filter "nginx-scanner" '1.2.3.4 - - [10/Mar/2026:20:00:01 +1100] "GET /wp-admin/install.php HTTP/1.1" 403 150'

# 4. Nginx Sensitive Files
check_filter "nginx-sensitive-files" '1.2.3.4 - - [10/Mar/2026:20:00:01 +1100] "GET /.env HTTP/1.1" 404 150'
check_filter "nginx-sensitive-files" '1.2.3.4 - - [10/Mar/2026:20:00:01 +1100] "GET /backup.sql HTTP/1.1" 403 150'

# 5. WordPress Login
check_filter "nginx-wp-login" '1.2.3.4 - - [10/Mar/2026:20:00:01 +1100] "POST /wp-login.php HTTP/1.1" 200 150'
check_filter "nginx-wp-login" '62.60.130.227 - - [04/Apr/2026:21:28:24 +0000] "GET /wp-admin/index.php HTTP/1.1" 302 5'

# 5b. WordPress WP-Cron
check_filter "nginx-wp-cron" '1.2.3.4 - - [10/Mar/2026:20:00:01 +1100] "POST /wp-cron.php HTTP/1.1" 200 150'
check_filter "nginx-wp-cron" '1.2.3.4 - - [10/Mar/2026:20:00:01 +1100] "POST /wp-cron.php?doing_wp_cron=123.456 HTTP/1.1" 200 150'
check_filter "nginx-wp-cron" '209.38.89.160 - - [04/Apr/2026:01:44:33 +0000] "POST /wp-cron.php?doing_wp_cron=1775267013.7797780036926269531250 HTTP/1.1" 504 176 "-" "WordPress/6.7.5; https://mydigitalstylist.com.au"'

# 5c. PHP Probes (Shell hunting/Backdoors)
check_filter "nginx-php-probes" '13.75.213.214 - - [04/Apr/2026:06:20:25 +0000] "GET /edit.php HTTP/1.1" 404 196'
check_filter "nginx-php-probes" '13.75.213.214 - - [04/Apr/2026:06:20:31 +0000] "GET /wp-content/uploads/admin.php HTTP/1.1" 404 196'

# 5d. XML-RPC Flooding
check_filter "nginx-xmlrpc" '45.67.221.84 - - [04/Apr/2026:20:46:10 +0000] "POST //xmlrpc.php HTTP/1.1" 200 466'
check_filter "nginx-xmlrpc" '1.2.3.4 - - [10/Mar/2026:20:00:01 +1100] "POST /xmlrpc.php HTTP/1.1" 200 150'

# 6. AI Scrapers
check_filter "nginx-ai-scrapers" '1.2.3.4 - - [10/Mar/2026:20:00:01 +1100] "GET /blog-post HTTP/1.1" 200 150 "-" "Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; GPTBot/1.2; +https://openai.com/gptbot)"'

# 7. Nginx Exploits (now scoped to query strings only)
check_filter "nginx-exploits" '1.2.3.4 - - [10/Mar/2026:20:00:01 +1100] "GET /?id=1+union+select+1 HTTP/1.1" 200 150'
check_filter "nginx-exploits" '1.2.3.4 - - [10/Mar/2026:20:00:01 +1100] "GET /%3Cscript%3Ealert(1)%3C/script%3E HTTP/1.1" 200 150'
check_filter "nginx-exploits" '1.2.3.4 - - [10/Mar/2026:20:00:01 +1100] "GET /index.php?file=../../etc/passwd HTTP/1.1" 200 150'

# 7b. WordPress REST API (user enumeration)
check_filter "nginx-wp-rest" '1.2.3.4 - - [10/Mar/2026:20:00:01 +1100] "GET /wp-json/wp/v2/users HTTP/1.1" 200 150'
check_filter "nginx-wp-rest" '1.2.3.4 - - [10/Mar/2026:20:00:01 +1100] "GET /wp-json/yoast HTTP/1.1" 200 150'

# 7c. Directory Listing (nginx error log)
check_filter "nginx-dir-list" '2026/04/06 04:44:07 [error] 500316#500316: *154232 directory index of "/var/www/bymilla.au/wp-includes/Text/Diff/Engine/" is forbidden, client: 52.187.249.150, server: bymilla.au, request: "GET /wp-includes/Text/Diff/Engine/ HTTP/1.1", host: "bymilla.au"'
check_filter "nginx-dir-list" '2026/04/06 04:44:10 [error] 500316#500316: *154232 directory index of "/var/www/bymilla.au/wp-includes/" is forbidden, client: 52.187.249.150, server: bymilla.au, request: "GET /wp-includes/ HTTP/1.1", host: "bymilla.au"'
check_filter "nginx-dir-list" '2026/04/06 04:44:12 [error] 500316#500316: *154232 directory index of "/var/www/bymilla.au/wp-admin/css/colors/" is forbidden, client: 52.187.249.150, server: bymilla.au, request: "GET /wp-admin/css/colors/ HTTP/1.1", host: "bymilla.au"'

echo "------------------------------------------------"
echo "Check complete."