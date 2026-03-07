# NGINX HARDENING & AUTOMATED IP BLOCKING - DOCUMENTATION
A high-performance security suite for Nginx servers that automates the
detection and blocking of malicious actors using Fail2Ban and UFW.

This system is specifically designed to handle "background noise"
(scanners, bots, and crawlers) without manual intervention.

## FEATURES
- **Zero-False-Positive Honeypots**: Traps bots looking for .env, .git,
and sensitive PHP files.
- **Automatic UFW Integration**: Instantly injects DENY rules into the
system firewall.
- **Cloudflare Ready**: Pre-configured to handle CF-Connecting-IP
headers (Real IP).
- **AI Scraper Blocking**: Limits aggressive AI crawlers (GPTBot,
ClaudeBot, etc.) to prevent high CPU load.
- **Recidive Jail**: Provides 7-day bans for "repeat offenders" who get banned multiple times.
- **Tarpitting**: Slows down requests for sensitive file types (SQL/Backups)
to waste attacker resources.

## INSTALLATION
Download the script: Save the bash script as `harden.sh`.

Make it executable:
Command: `chmod +x harden.sh`

Run as root:
Command: `sudo ./harden.sh`

## SYSTEM ARCHITECTURE
- **Nginx Snippet**: Redirects malicious patterns to a dedicated
'honeypot.log'.
- **Fail2Ban Filters**: Monitors both standard access logs and the
honeypot log for specific regex patterns.
- **Jails**: Defines the thresholds (e.g., 5 errors in 1 min = 1 hour ban).
- **UFW Action**: Executes the `/usr/sbin/ufw insert 1 deny` command to
block the IP globally.

## MAINTENANCE & COMMANDS
### CHECK CURRENTLY BANNED IPs:
```bash
sudo ufw status numbered
```

### CHECK FAIL2BAN ACTIVITY:
#### View all active jails:
```bash
sudo fail2ban-client status
```

#### View status of a specific jail (e.g., honeypot):
```bash
sudo fail2ban-client status nginx-honeypot
```

### UNBAN YOURSELF:
If you accidentally trigger a trap while developing:
```bash
sudo fail2ban-client set <jail-name> unbanip <your-ip>
```

### WHITELISTING:
To prevent a specific IP from ever being banned, add it to
`/etc/fail2ban/jail.local` under the `[DEFAULT]` section:
```bash
ignoreip = 127.0.0.1/8 ::1 <YOUR_IP_HERE>
```

## IMPORTANT NOTES
- **REAL IP**: Ensure your Nginx domain configurations include
`include snippets/security-traps.conf;` within their server blocks.
- **SSH SAFETY**: The script automatically allows SSH (Port 22). If you use a custom SSH port, update the script before running.
- **LOG ROTATION**: Ensure your /etc/logrotate.d/nginx configuration
handles the new `honeypot.log`.