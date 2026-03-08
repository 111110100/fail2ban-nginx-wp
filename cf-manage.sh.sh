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
    echo "Usage: $0 {list|ban|unban} [IP]"
    echo "  list         - List all active Account-level blocks"
    echo "  ban [IP]     - Ban an IP globally"
    echo "  unban [IP]   - Unban an IP globally"
    exit 1
}

case "$1" in
    list)
        echo "Fetching active blocks for Account: $CF_ACCOUNT_ID..."
        curl -s -X GET "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/firewall/access_rules/rules?mode=block&per_page=100" \
             -H "Authorization: Bearer $CF_API_TOKEN" \
             -H "Content-Type: application/json" | jq -r '.result[] | "[\(.id)] \(.configuration.value) - \(.notes)"'
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
        echo "Searching for Rule ID for IP: $2..."
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

    *)
        usage
        ;;
esac