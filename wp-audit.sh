#!/bin/bash

# ==============================================================================
# WORDPRESS SECURITY & UPDATE AUDITOR
# ==============================================================================
# Requirements: wp-cli, jq (for JSON output)
# Usage: ./wp-audit.sh /var/www/html [json|csv|screen]
# ==============================================================================

WP_PATH="${1:-.}"
OUTPUT_FORMAT="${2:-screen}"

# Colors for screen output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check dependencies
if ! command -v wp &> /dev/null; then
    echo "Error: 'wp' command not found. Please install wp-cli."
    exit 1
fi

if [[ "$OUTPUT_FORMAT" == "json" ]] && ! command -v jq &> /dev/null; then
    echo "Error: 'jq' is required for JSON output."
    exit 1
fi

# Validate WordPress path
if ! wp core is-installed --path="$WP_PATH" &> /dev/null; then
    echo "Error: No WordPress installation found at $WP_PATH"
    exit 1
fi

# --- DATA GATHERING ---

# 1. Updates
CORE_UPDATE=$(wp core check-update --path="$WP_PATH" --format=json 2>/dev/null | jq -r '.[0].version // "up-to-date"')
PLUGIN_UPDATES=$(wp plugin list --path="$WP_PATH" --update=available --format=count 2>/dev/null)
THEME_UPDATES=$(wp theme list --path="$WP_PATH" --update=available --format=count 2>/dev/null)

# 2. Integrity (Non-standard files)
CHECKSUM_ERRORS=$(wp core verify-checksums --path="$WP_PATH" 2>&1 | grep -c "Error" || echo 0)

# 3. Security Config
DEBUG_MODE=$(wp config get WP_DEBUG --path="$WP_PATH" 2>/dev/null || echo "false")

# 4. Permissions (Check for 777 or world-writable)
WRITABLE_FILES=$(find "$WP_PATH" -maxdepth 2 -not -path '*/.*' -perm -o+w | wc -l)

# --- OUTPUT GENERATION ---

case "$OUTPUT_FORMAT" in
    json)
        jq -n \
            --arg path "$WP_PATH" \
            --arg core "$CORE_UPDATE" \
            --arg plugins "$PLUGIN_UPDATES" \
            --arg themes "$THEME_UPDATES" \
            --arg checksums "$CHECKSUM_ERRORS" \
            --arg debug "$DEBUG_MODE" \
            --arg writable "$WRITABLE_FILES" \
            '{timestamp: now|strflocaltime("%Y-%m-%d %H:%M:%S"), path: $path, core_update: $core, plugin_updates: $plugins, theme_updates: $themes, checksum_errors: $checksums, wp_debug: $debug, world_writable_files: $writable}'
        ;;
    csv)
        echo "Timestamp,Path,CoreUpdate,PluginUpdates,ThemeUpdates,ChecksumErrors,WP_Debug,WorldWritable"
        echo "$(date '+%Y-%m-%d %H:%M:%S'),$WP_PATH,$CORE_UPDATE,$PLUGIN_UPDATES,$THEME_UPDATES,$CHECKSUM_ERRORS,$DEBUG_MODE,$WRITABLE_FILES"
        ;;
    *)
        echo -e "------------------------------------------------"
        echo -e "🔍 WORDPRESS AUDIT: $WP_PATH"
        echo -e "------------------------------------------------"
        
        # Core Status
        if [[ "$CORE_UPDATE" == "up-to-date" ]]; then
            echo -e "Core:      [${GREEN}OK${NC}] Up to date"
        else
            echo -e "Core:      [${RED}UPDATE${NC}] New version available: $CORE_UPDATE"
        fi

        # Plugins/Themes
        [[ $PLUGIN_UPDATES -gt 0 ]] && echo -e "Plugins:   [${YELLOW}WARN${NC}] $PLUGIN_UPDATES updates available" || echo -e "Plugins:   [${GREEN}OK${NC}] All plugins updated"
        [[ $THEME_UPDATES -gt 0 ]] && echo -e "Themes:    [${YELLOW}WARN${NC}] $THEME_UPDATES updates available" || echo -e "Themes:    [${GREEN}OK${NC}] All themes updated"

        # Integrity
        if [[ $CHECKSUM_ERRORS -eq 0 ]]; then
            echo -e "Integrity: [${GREEN}OK${NC}] Core checksums pass"
        else
            echo -e "Integrity: [${RED}FAIL${NC}] Non-standard files or modifications detected!"
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
        ;;
esac
