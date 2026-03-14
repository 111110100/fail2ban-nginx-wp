#!/bin/bash

# ==============================================================================
# WORDPRESS SECURITY & UPDATE AUDITOR
# ==============================================================================
# Requirements: wp-cli, jq (for JSON output)
# Usage: ./wp-audit.sh /var/www/html [json|csv|screen]
# ==============================================================================

WP_PATH="${1:-.}"
OUTPUT_FORMAT="${2:-screen}"

# Resolve to absolute path
WP_PATH=$(cd "$WP_PATH" 2>/dev/null && pwd)

# Log file setup - save in WordPress directory to avoid permission issues
LOG_FILE="${WP_PATH}/wp-audit-$(date '+%d-%m-%Y').log"

# Colors for screen output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Logging function
log() {
    echo "$1" >> "$LOG_FILE"
}

# Bypass any wp aliases (e.g., sudo -u www-data wp) to run with current user
unalias wp 2>/dev/null

# Check dependencies
if ! command -v wp &> /dev/null; then
    echo "Error: 'wp' command not found. Please install wp-cli."
    exit 1
fi

if [[ "$OUTPUT_FORMAT" == "json" ]] && ! command -v jq &> /dev/null; then
    echo "Error: 'jq' is required for JSON output."
    exit 1
fi

# Initialize log file
echo "========================================" > "$LOG_FILE"
echo "WORDPRESS AUDIT LOG - $(date '+%d-%m-%Y %H:%M:%S')" >> "$LOG_FILE"
echo "========================================" >> "$LOG_FILE"
log "WordPress Path: $WP_PATH"
log ""

# Validate WordPress path
if ! wp core version --path="$WP_PATH" &> /dev/null; then
    echo "Error: No WordPress installation found at $WP_PATH"
    exit 1
fi

# --- DATA GATHERING ---

# 1. Updates - Core
echo -e "⏳ Checking WordPress core updates..."
log "=== CORE UPDATES ==="
CORE_UPDATE_JSON=$(wp core check-update --path="$WP_PATH" --format=json 2>/dev/null || echo "[]")
CORE_CURRENT=$(wp core version --path="$WP_PATH" 2>/dev/null)
log "Current Version: $CORE_CURRENT"
if [[ -n "$CORE_UPDATE_JSON" && "$CORE_UPDATE_JSON" != "[]" && "$CORE_UPDATE_JSON" != "" ]]; then
    CORE_NEW=$(echo "$CORE_UPDATE_JSON" | jq -r '.[0].version // empty' 2>/dev/null)
    if [[ -n "$CORE_NEW" ]]; then
        CORE_STATUS="outdated"
        log "Status: OUTDATED"
        log "Available Version: $CORE_NEW"
    else
        CORE_NEW=""
        CORE_STATUS="up-to-date"
        log "Status: Up to date"
    fi
else
    CORE_NEW=""
    CORE_STATUS="up-to-date"
    log "Status: Up to date"
fi
log ""

# 2. Updates - Plugins (get full details)
echo -e "⏳ Checking plugin updates..."
log "=== PLUGIN UPDATES ==="
PLUGIN_UPDATES_JSON=$(wp plugin list --path="$WP_PATH" --update=available --format=json 2>/dev/null || echo "[]")
if [[ "$PLUGIN_UPDATES_JSON" == "[]" || -z "$PLUGIN_UPDATES_JSON" ]]; then
    PLUGIN_UPDATES_COUNT=0
    log "All plugins are up to date"
else
    PLUGIN_UPDATES_COUNT=$(echo "$PLUGIN_UPDATES_JSON" | jq 'length' 2>/dev/null | tr -d '\n')
    [[ -z "$PLUGIN_UPDATES_COUNT" ]] && PLUGIN_UPDATES_COUNT=0
    log "Outdated Plugins: $PLUGIN_UPDATES_COUNT"
    log "Details:"
    # Parse each plugin and log individually to handle multiline output
    while IFS= read -r line; do
        [[ -n "$line" ]] && log "  $line"
    done < <(echo "$PLUGIN_UPDATES_JSON" | jq -r '.[] | "\(.name): \(.version) -> \(.update_version)"' 2>/dev/null)
fi
log ""

# 3. Updates - Themes (get full details)
echo -e "⏳ Checking theme updates..."
log "=== THEME UPDATES ==="
THEME_UPDATES_JSON=$(wp theme list --path="$WP_PATH" --update=available --format=json 2>/dev/null || echo "[]")
if [[ "$THEME_UPDATES_JSON" == "[]" || -z "$THEME_UPDATES_JSON" ]]; then
    THEME_UPDATES_COUNT=0
    log "All themes are up to date"
else
    THEME_UPDATES_COUNT=$(echo "$THEME_UPDATES_JSON" | jq 'length' 2>/dev/null | tr -d '\n')
    [[ -z "$THEME_UPDATES_COUNT" ]] && THEME_UPDATES_COUNT=0
    log "Outdated Themes: $THEME_UPDATES_COUNT"
    log "Details:"
    # Parse each theme and log individually to handle multiline output
    while IFS= read -r line; do
        [[ -n "$line" ]] && log "  $line"
    done < <(echo "$THEME_UPDATES_JSON" | jq -r '.[] | "\(.name): \(.version) -> \(.update_version)"' 2>/dev/null)
fi
log ""

# 4. Integrity (Non-standard files)
echo -e "⏳ Checking integrity..."
log "=== INTEGRITY CHECK ==="
CHECKSUM_OUTPUT=$(wp core verify-checksums --path="$WP_PATH" 2>&1)
CHECKSUM_ERRORS=$(echo "$CHECKSUM_OUTPUT" | grep -c "Error" 2>/dev/null | tr -d '\n' || echo 0)
[[ -z "$CHECKSUM_ERRORS" ]] && CHECKSUM_ERRORS=0
log "Checksum Errors: $CHECKSUM_ERRORS"
NON_STANDARD_FILES=$(echo "$CHECKSUM_OUTPUT" | grep -E "^\s+" | sed 's/^[[:space:]]*//' || echo "")
if [[ -n "$NON_STANDARD_FILES" ]]; then
    log "Non-standard files detected:"
    NON_STD_FORMATTED=$(echo "$NON_STANDARD_FILES" | grep -v '^$' | sed 's/^/  - /')
    log "$NON_STD_FORMATTED"
else
    log "No non-standard files detected"
fi
log ""

# 5. Security Config
echo -e "⏳ Checking security configuration..."
log "=== SECURITY CONFIG ==="
DEBUG_MODE=$(wp config get WP_DEBUG --path="$WP_PATH" 2>/dev/null || echo "false")
log "WP_DEBUG: $DEBUG_MODE"
log ""

# 6. Permissions (Check for 777 or world-writable)
echo -e "⏳ Checking file permissions..."
log "=== FILE PERMISSIONS ==="
WRITABLE_FILES=$(find "$WP_PATH" -maxdepth 2 -not -path '*/.*' -perm -o+w | wc -l | tr -d ' \n')
WRITABLE_FILES_LIST=$(find "$WP_PATH" -maxdepth 2 -not -path '*/.*' -perm -o+w 2>/dev/null)
log "World-writable files: $WRITABLE_FILES"
if [[ -n "$WRITABLE_FILES_LIST" ]]; then
    log "World-writable file list:"
    WRITABLE_FORMATTED=$(echo "$WRITABLE_FILES_LIST" | sed 's/^/  - /')
    log "$WRITABLE_FORMATTED"
else
    log "No world-writable files found"
fi
log ""

# --- OUTPUT GENERATION ---

case "$OUTPUT_FORMAT" in
    json)
        # Build non-standard files array
        NON_STD_ARRAY="[]"
        if [[ -n "$NON_STANDARD_FILES" ]]; then
            NON_STD_ARRAY=$(echo "$NON_STANDARD_FILES" | grep -v '^$' | jq -R . | jq -s . 2>/dev/null || echo "[]")
        fi
        jq -n \
            --arg path "$WP_PATH" \
            --arg core_current "$CORE_CURRENT" \
            --arg core_status "$CORE_STATUS" \
            --arg core_new "$CORE_NEW" \
            --argjson plugins "$PLUGIN_UPDATES_JSON" \
            --argjson themes "$THEME_UPDATES_JSON" \
            --arg checksums "$CHECKSUM_ERRORS" \
            --argjson nonstandard "$NON_STD_ARRAY" \
            --arg debug "$DEBUG_MODE" \
            --arg writable "$WRITABLE_FILES" \
            '{
                timestamp: now|strflocaltime("%Y-%m-%d %H:%M:%S"),
                path: $path,
                core: {status: $core_status, current: $core_current, available: $core_new},
                plugins: {updates: $plugins},
                themes: {updates: $themes},
                checksum_errors: $checksums,
                non_standard_files: $nonstandard,
                wp_debug: $debug,
                world_writable_files: $writable
            }'
        ;;
    csv)
        echo "Timestamp,Path,CoreCurrent,CoreAvailable,PluginUpdates,ThemeUpdates,ChecksumErrors,NonStandardFiles,WP_Debug,WorldWritable"
        echo "$(date '+%Y-%m-%d %H:%M:%S'),$WP_PATH,$CORE_CURRENT,$([ "$CORE_STATUS" = "outdated" ] && echo "$CORE_NEW" || echo "up-to-date"),$PLUGIN_UPDATES_COUNT,$THEME_UPDATES_COUNT,$CHECKSUM_ERRORS,$(echo "$NON_STANDARD_FILES" | grep -v '^$' | wc -l),$DEBUG_MODE,$WRITABLE_FILES"
        ;;
    *)
        echo -e "------------------------------------------------"
        echo -e "🔍 WORDPRESS AUDIT: $WP_PATH"
        echo -e "------------------------------------------------"
        echo ""

        # Core Status
        if [[ "$CORE_STATUS" == "up-to-date" ]]; then
            echo -e "Core:      [${GREEN}OK${NC}] Up to date ($CORE_CURRENT)"
        else
            echo -e "Core:      [${RED}UPDATE${NC}] $CORE_CURRENT → $CORE_NEW"
        fi

        # Plugins
        if [[ $PLUGIN_UPDATES_COUNT -gt 0 ]]; then
            echo -e "Plugins:   [${YELLOW}WARN${NC}] $PLUGIN_UPDATES_COUNT updates available"
            echo "$PLUGIN_UPDATES_JSON" | jq -r '.[] | "             \(.name): \(.version) → \(.update_version)"' 2>/dev/null
        else
            echo -e "Plugins:   [${GREEN}OK${NC}] All plugins updated"
        fi

        # Themes
        if [[ $THEME_UPDATES_COUNT -gt 0 ]]; then
            echo -e "Themes:    [${YELLOW}WARN${NC}] $THEME_UPDATES_COUNT updates available"
            echo "$THEME_UPDATES_JSON" | jq -r '.[] | "             \(.name): \(.version) → \(.update_version)"' 2>/dev/null
        else
            echo -e "Themes:    [${GREEN}OK${NC}] All themes updated"
        fi

        # Integrity
        if [[ $CHECKSUM_ERRORS -eq 0 ]]; then
            echo -e "Integrity: [${GREEN}OK${NC}] Core checksums pass"
        else
            echo -e "Integrity: [${RED}FAIL${NC}] Non-standard files detected!"
            echo "$NON_STANDARD_FILES" | grep -v '^$' | while read -r file; do
                echo -e "             $file"
            done
        fi

        # Security
        [[ "$DEBUG_MODE" == "true" ]] && echo -e "Security:  [${RED}RISK${NC}] WP_DEBUG is ENABLED" || echo -e "Security:  [${GREEN}OK${NC}] WP_DEBUG is disabled"

        # Permissions
        if [[ $WRITABLE_FILES -eq 0 ]]; then
            echo -e "Perms:     [${GREEN}OK${NC}] No world-writable files found"
        else
            echo -e "Perms:     [${RED}RISK${NC}] $WRITABLE_FILES world-writable files detected!"
        fi
        echo -e "------------------------------------------------"
        echo -e "📄 Log saved to: $LOG_FILE"
        ;;
esac

# Finalize log
log "========================================"
log "AUDIT COMPLETED - $(date '+%d-%m-%Y %H:%M:%S')"
log "========================================"
