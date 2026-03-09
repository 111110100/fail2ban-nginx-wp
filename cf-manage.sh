#!/bin/bash

# --- CONFIGURATION ---
CF_ACCOUNT_ID=""
CF_API_TOKEN=""
# ---------------------

# Dependency Check
if ! command -v jq &> /dev/null; then
    echo "Error: 'jq' is not installed. Run: sudo apt install jq"
    exit 1
fi

if [[ -z "$CF_ACCOUNT_ID" || -z "$CF_API_TOKEN" ]]; then
    echo "Error: Please edit the script and add your Cloudflare Account ID and Token."
    exit 1
fi

usage() {
    echo "Usage: $0 {list|ban|unban|clean|info} [IP/Days]"
    echo "  list          - List ALL active Account-level blocks (paginated)"
    echo "  ban [IP]      - Ban an IP globally"
    echo "  unban [IP]    - Unban an IP globally"
    echo "  clean [days]  - Remove bans older than X days (default: 7)"
    echo "  info [IP]     - Show detailed block info + Geo/ISP lookup"
    exit 1
}

case "$1" in
    list)
        echo "Fetching all active blocks for Account: $CF_ACCOUNT_ID..."
        PAGE=1
        TOTAL_COUNT=0

        while true; do
            RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/firewall/access_rules/rules?mode=block&per_page=100&page=$PAGE" \
                -H "Authorization: Bearer $CF_API_TOKEN" \
                -H "Content-Type: application/json")

            # Extract and print rules from current page
            RULES=$(echo "$RESPONSE" | jq -r '.result[] | "[\(.id)] \(.configuration.value) - \(.notes) (Created: \(.created_on))"')

            if [[ -z "$RULES" ]]; then break; fi

            echo "$RULES"

            # Count for summary
            PAGE_COUNT=$(echo "$RESPONSE" | jq '.result | length')
            TOTAL_COUNT=$((TOTAL_COUNT + PAGE_COUNT))

            # Check if there is another page
            TOTAL_PAGES=$(echo "$RESPONSE" | jq -r '.result_info.total_pages')
            if [[ "$PAGE" -ge "$TOTAL_PAGES" ]]; then break; fi
            ((PAGE++))
        done
        echo "------------------------------------------------"
        echo "Total IPs found: $TOTAL_COUNT"
        ;;

    info)
        if [[ -z "$2" ]]; then usage; fi
        IP="$2"
        echo "------------------------------------------------"
        echo " INFO & GEO LOOKUP FOR: $IP"
        echo "------------------------------------------------"

        # 1. Cloudflare Status Check
        CF_RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/firewall/access_rules/rules?configuration.target=ip&configuration.value=$IP&mode=block" \
                  -H "Authorization: Bearer $CF_API_TOKEN" \
                  -H "Content-Type: application/json")

        CF_COUNT=$(echo "$CF_RESPONSE" | jq '.result | length')

        if [[ "$CF_COUNT" -eq 0 ]]; then
            echo "Cloudflare Status: NOT BLOCKED"
        else
            echo "Cloudflare Status: BLOCKED"
            echo "$CF_RESPONSE" | jq -r '.result[0] | "Rule ID: \(.id)\nNotes: \(.notes)\nCreated: \(.created_on)"'
        fi

        echo "------------------------------------------------"
        echo " GEOLOCATION & NETWORK INFO (via ip-api.com)"
        echo "------------------------------------------------"

        # 2. Public IP Lookup (Switching to ip-api.com for better rate limits)
        GEO=$(curl -s "http://ip-api.com/json/$IP")

        if [[ $(echo "$GEO" | jq -r '.status') == "fail" ]]; then
            echo "Lookup Error: $(echo "$GEO" | jq -r '.message')"
        else
            echo "Country:  $(echo "$GEO" | jq -r '.country') ($(echo "$GEO" | jq -r '.countryCode'))"
            echo "Region:   $(echo "$GEO" | jq -r '.regionName') ($(echo "$GEO" | jq -r '.city'))"
            echo "ISP:      $(echo "$GEO" | jq -r '.isp')"
            echo "Org:      $(echo "$GEO" | jq -r '.as')"
            echo "Timezone: $(echo "$GEO" | jq -r '.timezone')"
        fi
        echo "------------------------------------------------"
        ;;

    ban)
        if [[ -z "$2" ]]; then usage; fi
        echo "Banning IP: $2..."
        curl -s -X POST "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/firewall/access_rules/rules" \
             -H "Authorization: Bearer $CF_API_TOKEN" \
             -H "Content-Type: application/json" \
             --data "{\"mode\":\"block\",\"configuration\":{\"target\":\"ip\",\"value\":\"$2\"},\"notes\":\"Manual Block via Script\"}" | jq .
        ;;

    unban)
        if [[ -z "$2" ]]; then usage; fi
        RULE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/firewall/access_rules/rules?configuration.target=ip&configuration.value=$2&mode=block" \
                  -H "Authorization: Bearer $CF_API_TOKEN" \
                  -H "Content-Type: application/json" | jq -r '.result[0].id')

        if [[ "$RULE_ID" == "null" || -z "$RULE_ID" ]]; then
            echo "Error: No active block found for IP: $2"
        else
            echo "Deleting Rule ID: $RULE_ID..."
            curl -s -X DELETE "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/firewall/access_rules/rules/$RULE_ID" \
                 -H "Authorization: Bearer $CF_API_TOKEN" \
                 -H "Content-Type: application/json" | jq .
        fi
        ;;

    clean)
        DAYS=${2:-7}
        CUTOFF=$(date -u -d "$DAYS days ago" +"%Y-%m-%dT%H:%M:%SZ")
        echo "Cleaning up bans older than $DAYS days (Cutoff: $CUTOFF)..."

        PAGE=1
        while true; do
            RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/firewall/access_rules/rules?mode=block&per_page=100&page=$PAGE" \
                -H "Authorization: Bearer $CF_API_TOKEN" \
                -H "Content-Type: application/json")

            RULES=$(echo "$RESPONSE" | jq -c '.result[]')
            if [[ -z "$RULES" ]]; then break; fi

            echo "$RULES" | while read -r rule; do
                R_ID=$(echo "$rule" | jq -r '.id')
                R_DATE=$(echo "$rule" | jq -r '.created_on')
                R_IP=$(echo "$rule" | jq -r '.configuration.value')
                R_NOTES=$(echo "$rule" | jq -r '.notes')

                if [[ "$R_DATE" < "$CUTOFF" ]]; then
                    if [[ "$R_NOTES" == *"PERMANENT"* ]]; then
                        echo "[SKIP] $R_IP is marked as permanent."
                    else
                        echo "[DELETE] Expiring ban for $R_IP (Created: $R_DATE)"
                        curl -s -X DELETE "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/firewall/access_rules/rules/$R_ID" \
                             -H "Authorization: Bearer $CF_API_TOKEN" \
                             -H "Content-Type: application/json" > /dev/null
                    fi
                fi
            done

            TOTAL_PAGES=$(echo "$RESPONSE" | jq -r '.result_info.total_pages')
            if [[ "$PAGE" -ge "$TOTAL_PAGES" ]]; then break; fi
            ((PAGE++))
        done
        echo "Cleanup finished."
        ;;

    *)
        usage
        ;;
esac
