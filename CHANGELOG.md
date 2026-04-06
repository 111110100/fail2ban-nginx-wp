# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Security Improvements
- **Fixed duplicate filters**: `nginx-honeypot` now targets specific honeypot paths instead of matching all 403s (same as `nginx-403`)
- **Improved recidive filter**: Uses official Fail2Ban regex pattern to properly detect ban notices
- **Scoped exploit filter**: SQL injection patterns now only match in query strings to reduce false positives
- **Added REST API jail**: New `nginx-wp-rest` jail blocks `/wp-json/wp/v2/users` enumeration and Yoast SEO API abuse

### Infrastructure
- **Credential management**: Moved Cloudflare credentials to `.env` file (copy from `.env.example`)
- **Added `.gitignore`**: Prevents accidental commits of `.env`, `*.log`, `*.sqlite3` files
- **Idempotent UFW rules**: Running `harden.sh` multiple times won't create duplicate Cloudflare IP allow rules
- **Error handling**: Critical operations (UFW enable, Fail2Ban restart) now exit on failure instead of continuing silently
- **Auto-generated snippets**: `harden.sh` now creates both `cloudflare-ips.conf` and `security-traps.conf` in `/etc/nginx/snippets/`
- **Dynamic MY_IP injection**: WP-Cron allow rule in `security-traps.conf` automatically includes your home IP from `.env`

### Script Improvements
- **Strict mode**: All scripts now use `set -euo pipefail` for better error detection
- **Fixed date comparison**: `cf-manage.sh clean` now uses epoch seconds for reliable date comparison across platforms
- **Fixed CSV output**: `wp-audit.sh` CSV mode now properly quotes all fields
- **New healthcheck script**: `healthcheck.sh` verifies all components (Fail2Ban, UFW, Nginx, Cloudflare API) are operational

### Documentation
- **Fixed typos**: Corrected `cf-manage.shi` → `cf-manage.sh`, `Inlcude` → `Include`
- **Removed dead references**: Removed reference to non-existent `fail2ban-cf-test.sh`
- **Updated setup instructions**: Clarified `.env` file usage instead of editing scripts directly
- **Collapsible config section**: Nginx real_ip config now in expandable section for readability

### Jails Added
| Jail Name | Max Retry | Find Time | Ban Time | Purpose |
|-----------|-----------|-----------|----------|---------|
| `nginx-wp-rest` | 3 | 600s | 86400s | WordPress REST API user enumeration |
