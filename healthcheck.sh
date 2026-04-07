#!/bin/bash

set -euo pipefail

# ==============================================================================
# SECURITY STACK HEALTHCHECK
# Verifies all components of the Fail2Ban + Nginx + UFW + Cloudflare stack
# ==============================================================================

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

check_pass() { echo -e "  [$GREEN✓$NC] $1"; ((PASS++)); }
check_fail() { echo -e "  [$RED✗$NC] $1"; ((FAIL++)); }
check_warn() { echo -e "  [$YELLOW!$NC] $1"; ((WARN++)); }

echo "================================================"
echo " 🔍 SECURITY STACK HEALTHCHECK"
echo "================================================"
echo ""

# 1. Fail2Ban Service
echo -e "${YELLOW}Fail2Ban Service${NC}"
if systemctl is-active --quiet fail2ban 2>/dev/null; then
    check_pass "Fail2Ban is running"
else
    check_fail "Fail2Ban is NOT running"
fi

# 2. Fail2Ban Jails
echo -e "\n${YELLOW}Fail2Ban Jails${NC}"
if command -v fail2ban-client &>/dev/null; then
    JAILS=$(fail2ban-client status 2>/dev/null | grep "Jail list" | cut -d: -f2 | tr ',' '\n' | sed 's/^ //g' || echo "")
    if [[ -n "$JAILS" ]]; then
        JAIL_COUNT=$(echo "$JAILS" | wc -w | tr -d ' ')
        check_pass "$JAIL_COUNT jails active"
        echo "  Active jails: $JAILS"
    else
        check_fail "No jails configured"
    fi

    # Check specific critical jails
    for jail in nginx-honeypot nginx-scanner recidive; do
        if fail2ban-client status "$jail" &>/dev/null; then
            BANNED=$(fail2ban-client status "$jail" 2>/dev/null | grep "Currently banned" | awk '{print $NF}' || echo "?")
            check_pass "Jail '$jail' active (banned: $BANNED)"
        else
            check_fail "Jail '$jail' is NOT active"
        fi
    done
else
    check_fail "fail2ban-client not found"
fi

# 3. UFW Status
echo -e "\n${YELLOW}UFW Firewall${NC}"
if command -v ufw &>/dev/null; then
    if ufw status 2>/dev/null | grep -q "Status: active"; then
        check_pass "UFW is active"
        RULE_COUNT=$(ufw status numbered 2>/dev/null | grep -c "\[.*\]" || true)
        check_pass "$RULE_COUNT rules loaded"
    else
        check_fail "UFW is NOT active"
    fi

    # Check Cloudflare IP whitelisting
    CF_RULES=$(ufw status numbered 2>/dev/null | grep -c "Cloudflare IP" || true)
    if [[ "$CF_RULES" -gt 0 ]]; then
        check_pass "$CF_RULES Cloudflare IP whitelist rules"
    else
        check_warn "No Cloudflare IP whitelist rules found"
    fi
else
    check_fail "UFW not installed"
fi

# 4. Nginx Configuration
echo -e "\n${YELLOW}Nginx Configuration${NC}"
if command -v nginx &>/dev/null; then
    if nginx -t 2>&1 | grep -q "syntax is ok"; then
        check_pass "Nginx config syntax is valid"
    else
        check_fail "Nginx config has errors"
        nginx -t 2>&1 | sed 's/^/    /'
    fi

    if systemctl is-active --quiet nginx 2>/dev/null; then
        check_pass "Nginx is running"
    else
        check_warn "Nginx is NOT running"
    fi

    # Check for security-traps.conf inclusion
    if grep -rq "security-traps.conf" /etc/nginx/ 2>/dev/null; then
        check_pass "security-traps.conf is included in Nginx"
    else
        check_warn "security-traps.conf not found in Nginx config"
    fi

    # Check for real_ip_header
    if grep -rq "real_ip_header" /etc/nginx/ 2>/dev/null; then
        check_pass "real_ip_header is configured"
    else
        check_warn "real_ip_header not found (Cloudflare IP may not be resolved correctly)"
    fi
else
    check_fail "Nginx not installed"
fi

# 5. Cloudflare API Connectivity
echo -e "\n${YELLOW}Cloudflare API${NC}"
# Load .env if available (current directory, then home directory)
ENV_FILE="$(dirname "$0")/.env"
if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
else
    ENV_FILE="$HOME/.env"
    if [[ -f "$ENV_FILE" ]]; then
        source "$ENV_FILE"
    fi
fi

if [[ -n "${CF_ACCOUNT_ID:-}" && -n "${CF_API_TOKEN:-}" ]]; then
    CF_TEST=$(curl -s -o /dev/null -w "%{http_code}" "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/firewall/access_rules/rules?per_page=1" \
        -H "Authorization: Bearer $CF_API_TOKEN" 2>/dev/null || echo "000")
    if [[ "$CF_TEST" == "200" ]]; then
        check_pass "Cloudflare API is reachable and authenticated"
    elif [[ "$CF_TEST" == "403" || "$CF_TEST" == "401" ]]; then
        check_fail "Cloudflare API authentication failed (HTTP $CF_TEST)"
    else
        check_warn "Cloudflare API returned HTTP $CF_TEST"
    fi
else
    check_warn "Cloudflare credentials not configured (set CF_ACCOUNT_ID and CF_API_TOKEN in .env)"
fi

# 6. Disk Space
echo -e "\n${YELLOW}Disk Space${NC}"
LOG_USAGE=$(df -h /var/log 2>/dev/null | tail -1 | awk '{print $5}' || echo "N/A")
if [[ "$LOG_USAGE" != "N/A" ]]; then
    USAGE_NUM=${LOG_USAGE%\%}
    if [[ "$USAGE_NUM" -gt 90 ]]; then
        check_fail "Log partition is ${USAGE_USAGE} full"
    elif [[ "$USAGE_NUM" -gt 75 ]]; then
        check_warn "Log partition is ${USAGE_USAGE} full"
    else
        check_pass "Log partition usage: ${USAGE_USAGE}"
    fi
fi

# 7. Fail2Ban Log Health
echo -e "\n${YELLOW}Fail2Ban Logs${NC}"
if [[ -f /var/log/fail2ban.log ]]; then
    LAST_ENTRY=$(tail -1 /var/log/fail2ban.log 2>/dev/null || echo "")
    if [[ -n "$LAST_ENTRY" ]]; then
        check_pass "Fail2Ban log exists and has entries"
        # Check if log is recent (within last hour)
        LAST_HOUR=$(tail -100 /var/log/fail2ban.log 2>/dev/null | grep -c "$(date +%Y-%m-%d)" || true)
        if [[ "$LAST_HOUR" -gt 0 ]]; then
            check_pass "Recent log entries found today"
        else
            check_warn "No log entries from today"
        fi
    else
        check_warn "Fail2Ban log is empty"
    fi
else
    check_warn "Fail2Ban log not found at /var/log/fail2ban.log"
fi

# Summary
echo ""
echo "================================================"
echo " SUMMARY"
echo "================================================"
echo -e "  ${GREEN}Passed:$NC $PASS"
echo -e "  ${RED}Failed:$NC $FAIL"
echo -e "  ${YELLOW}Warnings:$NC $WARN"
echo ""

if [[ "$FAIL" -eq 0 ]]; then
    echo -e "  ${GREEN}Overall: HEALTHY$NC"
else
    echo -e "  ${RED}Overall: ISSUES DETECTED - Review failures above$NC"
fi
echo "================================================"
