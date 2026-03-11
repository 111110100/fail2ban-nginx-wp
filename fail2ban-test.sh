#!/bin/bash

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

# 2. Nginx Honeypot
check_filter "nginx-honeypot" '1.2.3.4 - - [10/Mar/2026:20:00:01 +1100] "GET /admin-login.php HTTP/1.1" 403 150'

# 3. Nginx Scanner
check_filter "nginx-scanner" '1.2.3.4 - - [10/Mar/2026:20:00:01 +1100] "GET /.env HTTP/1.1" 403 150'
check_filter "nginx-scanner" '1.2.3.4 - - [10/Mar/2026:20:00:01 +1100] "GET /wp-admin/install.php HTTP/1.1" 403 150'

# 4. Nginx Sensitive Files
check_filter "nginx-sensitive-files" '1.2.3.4 - - [10/Mar/2026:20:00:01 +1100] "GET /.env HTTP/1.1" 404 150'
check_filter "nginx-sensitive-files" '1.2.3.4 - - [10/Mar/2026:20:00:01 +1100] "GET /backup.sql HTTP/1.1" 403 150'

# 5. AI Scrapers
check_filter "nginx-ai-scrapers" '1.2.3.4 - - [10/Mar/2026:20:00:01 +1100] "GET /blog-post HTTP/1.1" 200 150 "-" "Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; GPTBot/1.2; +https://openai.com/gptbot)"'

# 6. Nginx Exploits
check_filter "nginx-exploits" '1.2.3.4 - - [10/Mar/2026:20:00:01 +1100] "GET /?id=1+union+select+1 HTTP/1.1" 200 150'
check_filter "nginx-exploits" '1.2.3.4 - - [10/Mar/2026:20:00:01 +1100] "GET /<script>alert(1)</script> HTTP/1.1" 200 150'
check_filter "nginx-exploits" '1.2.3.4 - - [10/Mar/2026:20:00:01 +1100] "GET /index.php?file=../../etc/passwd HTTP/1.1" 200 150'

echo "------------------------------------------------"
echo "Check complete."