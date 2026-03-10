#!/bin/bash

# --- COLORS FOR OUTPUT ---
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo "------------------------------------------------"
echo "🔍 HARDEN.SH - REGEX SANITY CHECK"
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

    fail2ban-regex "$LOG_LINE" "$FILTER_PATH" > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}PASSED${NC}"
    else
        echo -e "${RED}FAILED (No Match)${NC}"
        # Detailed output on failure
        fail2ban-regex "$LOG_LINE" "$FILTER_PATH"
    fi
}

# --- DEFINE TEST CASES ---

# 1. Nginx 403 (Forbidden Access Spikes)
# Simulates a log entry where a bot is repeatedly hitting forbidden areas
check_filter "nginx-403" '1.2.3.4 - - [10/Mar/2026:20:00:01 +1100] "GET /phpmyadmin HTTP/1.1" 403 150'

# 2. Nginx Honeypot (Direct hit to your trap file)
# Assumes your honeypot log format matches your standard access log
check_filter "nginx-honeypot" '1.2.3.4 - - [10/Mar/2026:20:00:01 +1100] "GET /admin-login.php HTTP/1.1" 404 150'

# 3. AI Scrapers (User-Agent based blocking)
# Simulates a request from GPTBot which should trigger the ai-scrapers filter
check_filter "nginx-ai-scrapers" '1.2.3.4 - - [10/Mar/2026:20:00:01 +1100] "GET /blog-post HTTP/1.1" 200 150 "-" "Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; GPTBot/1.2; +https://openai.com/gptbot)"'

# 4. Previous Filters (Exploits & Sensitive Files)
check_filter "nginx-exploits" '1.2.3.4 - - [10/Mar/2026:20:00:01 +1100] "GET /?id=1+union+select+1 HTTP/1.1" 200 150'
check_filter "nginx-sensitive-files" '1.2.3.4 - - [10/Mar/2026:20:00:01 +1100] "GET /.env HTTP/1.1" 404 150'

echo "------------------------------------------------"
echo "Check complete."