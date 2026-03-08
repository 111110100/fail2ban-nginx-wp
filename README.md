# NGINX HARDENING & AUTOMATED IP BLOCKING - DOCUMENTATION
A high-performance security suite for Nginx servers that automates the detection and blocking of malicious actors using Fail2Ban and UFW.

This system is specifically designed to handle "background noise" (scanners, bots, and crawlers) without manual intervention.

## FEATURES
- **Cloudflare Edge Blocking**: Uses Account-level API to block IPs globally across all domains in your account.
- **Zero-False-Positive Honeypots**: Traps bots looking for .env, .git, and sensitive PHP files.
- **Full Security Suite**: Includes jails for 403 errors, scanners, sensitive files, and AI scrapers.
- **Automatic UFW Integration**: Instantly injects DENY rules into the local system firewall.
- **Recidive Jail**: Provides 7-day bans for repeat offenders.
- **AI Scraper Blocking**: Limits aggressive AI crawlers (GPTBot, ClaudeBot, etc.) to prevent high CPU load.

## CLOUDFLARE INTEGRATION SETUP
To enable Account-level blocking, you must configure the following in `harden.sh`:
1. **Account ID**: Log in to Cloudflare, click any domain, and find the 'Account ID' on the right-hand sidebar.
2. **API Token**: Create at 'My Profile' > 'API Tokens'.
   - Template: Custom Token
   - Permissions: [Account] | [Account Firewall Access Rules] | [Edit]
   - Resources: Include | All accounts
3. Make it executable: `chmod +x harden.sh`
4. Run as root: `sudo ./harden.sh`

## SYSTEM ARCHITECTURE
- **Cloudflare (Edge)**: First line of defense. Blocks IPs at the global network edge.
- **UFW (Local)**: Second line of defense. Protects origin IP from direct-to-IP attacks.
- **Fail2Ban**: Monitors logs (nginx access, honeypot, fail2ban logs) and triggers both actions.

## MAINTENANCE & COMMANDS
### CHECK CLOUDFLARE BANS:
Log into Cloudflare > Manage Account > Configurations > IP Access Rules. Rules added by this script are tagged with "Fail2Ban Global".

### CHECK LOCAL BANS:
```bash
sudo ufw status numbered
```

### CHECK FAIL2BAN ACTIVITY:
```bash
sudo fail2ban-client status
sudo fail2ban-client status nginx-honeypot
```

### UNBAN YOURSELF:
- Local: `sudo fail2ban-client set <jail-name> unbanip <your-ip>`
- Edge: Unban via Cloudflare Dashboard (IP Access Rules).


### FORCE FLUSH
To flush everything and restart services:
```bash
systemctl restart ufw && systemctl stop fail2ban && rm -f /var/lib/fail2ban/fail2ban.sqlite3 && systemctl start fail2ban
```

## IMPORTANT NOTES
- **REAL IP**: Ensure Nginx domain configs include `include snippets/security-traps.conf;`.
- **SSH**: Port 22 is allowed by default.
- **Package Check**: The script automatically skips installation of Nginx, Fail2Ban, etc., if they are already present.