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

### CF-MANAGE SCRIPT
This repo provides a script that allows your to list, manually ban and unban IPs blocked by Fail2Ban.

#### GET YOUR ACCOUNT ID FROM CLOUDFLARE
- Login to your Cloudflare Dashboard
- Click on any website/domain
- Look for **Account ID**
- Copy and paste into `CF_ACCOUNT_ID` in `harden.sh` and `cf-manage.sh`

#### CREATE NEW TOKEN
- Click on the person icon located on the upper right of the page
- Click **API Tokens**
- Click **Create Token**
- Look for **Custom Token**
- CLick on **Get Started**
- Under **Token name**, type in `Fail2Ban`
- Under **Permissions**, pick `Account` > `Account Firewall Access Rules` > `Edit`
- Under **Account Resources**, pick `Inlcude` > `All accounts`
- Under **IP Address Filtering**, you can include your own IPs from being blocked
- Click **Continue to summary**
- It should look like this: **All accounts - Account Firewall Access Rules:Edit**
- Click **Create Token**
- Test the token if working by copying and pasting the provided curl command
- If working, copy the token and paste it under `CF_API_TOKEN` in `harden.sh` and `cf-manage.shi`. You can only view this once so don't close the page unless you have completed this step.

#### CHECK BLOCKED IPS ON CLOUDFLARE
To list blocked IPs on Cloudflare:
```bash
cf-manage.sh list
```

#### BLOCK AN IP
To manually block an IP
```bash
cf-manage.sh ban <IP>
```

#### UNBLOCK AN IP
To manually unblock an IP
```bash
cf-manage.sh unban <IP>
```

#### SHOW INFO ON IP
To show information about a blocked IP (Dae of block, country, network)
```bash
cf-manage.sh info <IP>
```

#### AUTO-DELETE IP
The script can automatically delete IPs that were banned after a certain amount of days has passed
```bash
cf-manage.sh clean <DAYS>
```

#### SCHEDULE AUTO-DELETE IPS
You can also schedule them using a cron:
```bash
crontab -e
0 0 * * * /path/to/cf-manage.sh clean 7 >> /var/log/cf-clean.log 2>&1
```
will delete banned IPs from Cloudflare if they're older than 7 days

## IMPORTANT NOTES
- **REAL IP**: Ensure Nginx domain configs include `include snippets/security-traps.conf;`.
- **NGINX REAL IP HEADER**: Nginx real_ip_header should be enabled and configured:
```bash
# Tell Nginx to look at the header provided by the proxy (Cloudflare uses CF-Connecting-IP)
real_ip_header CF-Connecting-IP;

# IPv4
set_real_ip_from 173.245.48.0/20;
set_real_ip_from 103.21.244.0/22;
set_real_ip_from 103.22.200.0/22;
set_real_ip_from 103.31.4.0/22;
set_real_ip_from 141.101.64.0/18;
set_real_ip_from 108.162.192.0/18;
set_real_ip_from 190.93.240.0/20;
set_real_ip_from 188.114.96.0/20;
set_real_ip_from 197.234.240.0/22;
set_real_ip_from 198.41.128.0/17;
set_real_ip_from 162.158.0.0/15;
set_real_ip_from 104.16.0.0/13;
set_real_ip_from 104.24.0.0/14;
set_real_ip_from 172.64.0.0/13;
set_real_ip_from 131.0.72.0/22;

# IPv6
set_real_ip_from 2400:cb00::/32;
set_real_ip_from 2606:4700::/32;
set_real_ip_from 2803:f800::/32;
set_real_ip_from 2405:b500::/32;
set_real_ip_from 2405:8100::/32;
set_real_ip_from 2a06:98c0::/29;
set_real_ip_from 2c0f:f248::/32;
```
- **SSH**: Port 22 is allowed by default.
- **Package Check**: The script automatically skips installation of Nginx, Fail2Ban, etc., if they are already present.
- **Cloudflare Account ID/TOKEN**: For cf-manage.sh to work, you need your account ID and create an API token.