---
name: fail2ban-mgr
description: Manage Nginx hardening, Fail2Ban jails, and Cloudflare edge blocking. Use when auditing WordPress logs, modifying security filters, or troubleshooting IP bans and Cloudflare API integration.
---

# Fail2Ban & Nginx Security Management

This skill provides procedural knowledge for maintaining the high-performance security suite in this project.

## Core Workflows

### 1. Auditing IP Behavior
- **Identify Scanners**: Search Nginx logs for high frequencies of 403 or 404 errors.
- **WP-Cron Abuse**: Look for rapid POST requests to `wp-cron.php`. Legitimate cron jobs are infrequent; bursts of 5+ in seconds indicate abuse.
- **Troubleshoot "Not Banning"**: If an IP is logged but not banned:
  1. Check `fail2ban.log` for "Ignore" messages (often due to Cloudflare IPs in `ignoreip`).
  2. Verify Nginx `real_ip` configuration is working.

### 2. Modifying Filters
When adding or updating filters in `/etc/fail2ban/filter.d/`:
1. Use `fail2ban-regex` to test a sample log line.
2. Update the corresponding `harden.sh` section to persist the change.
3. **Mandatory**: Run `./fail2ban-test.sh` to ensure no regressions.

### 3. Managing Bans
- **Local (UFW)**: Use `sudo ufw status numbered` or `sudo fail2ban-client status <jail>`.
- **Global (Cloudflare)**: Use `./cf-manage.sh list` or `./cf-manage.sh info <IP>`.
- **Cleanup**: Schedule periodic purges of old bans using `./cf-manage.sh clean <DAYS>`.

## Key Resources
- **Jail reference**: See [jails.md](references/jails.md) for thresholds and ban times.
- **Troubleshooting**: See `/var/log/fail2ban.log` and `/var/log/nginx/error.log`.
