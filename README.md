# NGINX HARDENING & AUTOMATED IP BLOCKING - DOCUMENTATION
A high-performance security suite for Nginx servers that automates the detection and blocking of malicious actors using Fail2Ban and UFW.

This system is specifically designed to handle "background noise" (scanners, bots, and crawlers) without manual intervention.

## FEATURES
- **Cloudflare Edge Blocking**: Uses Account-level API to block IPs globally across all domains in your account.
- **Zero-False-Positive Honeypots**: Traps bots looking for .env, .git, and sensitive PHP files.
- **Full Security Suite**: Includes jails for 403 errors, scanners, sensitive files, AI scrapers, and REST API enumeration.
- **Automatic UFW Integration**: Instantly injects DENY rules into the local system firewall.
- **Recidive Jail**: Provides 7-day bans for repeat offenders.
- **AI Scraper Blocking**: Limits aggressive AI crawlers (GPTBot, ClaudeBot, etc.) to prevent high CPU load.
- **Health Monitoring**: Built-in healthcheck script to verify all components are operational.

## CLOUDFLARE INTEGRATION SETUP
To enable Account-level blocking, configure your credentials in a `.env` file (copy from `.env.example`):
1. **Account ID**: Log in to Cloudflare, click any domain, and find the 'Account ID' on the right-hand sidebar.
2. **API Token**: Create at 'My Profile' > 'API Tokens'.
   - Template: Custom Token
   - Permissions: [Account] | [Account Firewall Access Rules] | [Edit]
   - Resources: Include | All accounts
3. Run as root: `sudo ./harden.sh`

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

### RUN HEALTHCHECK:
```bash
sudo ./healthcheck.sh
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
This repo provides a script that allows you to list, manually ban and unban IPs blocked by Fail2Ban. Credentials are loaded from your `.env` file automatically.

#### GET YOUR ACCOUNT ID FROM CLOUDFLARE
- Login to your Cloudflare Dashboard
- Click on any website/domain
- Look for **Account ID**
- Copy and paste into `CF_ACCOUNT_ID` in your `.env` file

#### CREATE NEW TOKEN
- Click on the person icon located on the upper right of the page
- Click **API Tokens**
- Click **Create Token**
- Look for **Custom Token**
- CLick on **Get Started**
- Under **Token name**, type in `Fail2Ban`
- Under **Permissions**, pick `Account` > `Account Firewall Access Rules` > `Edit`
- Under **Account Resources**, pick `Include` > `All accounts`
- Under **IP Address Filtering**, you can include your own IPs from being blocked
- Click **Continue to summary**
- It should look like this: **All accounts - Account Firewall Access Rules:Edit**
- Click **Create Token**
- Test the token if working by copying and pasting the provided curl command
- If working, copy the token and paste it under `CF_API_TOKEN` in your `.env` file. You can only view this once so don't close the page unless you have completed this step.

#### CHECK BLOCKED IPS ON CLOUDFLARE
To list blocked IPs on Cloudflare:
```bash
cf-manage.sh list
```
It will look something like this:
```bash
Fetching active blocks for Account: <YOUR ACCOUNT ID>
[aeafb1a9df5741c7a5eefb8c7a1a1ad2] 146.190.63.48 - Fail2Ban:  (Created: 2026-03-09T10:28:45.438430241Z)
[0e419716f9b941a8a93a994b9d2c8f76] 20.212.32.182 - Fail2Ban:  (Created: 2026-03-09T10:15:56.924370237Z)
[789a7f3fc8514eec8468de8167a2cad7] 92.118.39.72 - Fail2Ban:  (Created: 2026-03-09T10:12:53.926739447Z)
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
It will look something like this:
```bash
./cf-manage.sh info 222.108.0.231
------------------------------------------------
 LOGOUT & GEO LOOKUP FOR: 222.108.0.231
------------------------------------------------
Cloudflare Status: BLOCKED
Rule ID: aa493982d7f34385bed093edb5432e95
Notes: Fail2Ban:
Created: 2026-03-09T09:56:41.466915704Z
------------------------------------------------
 GEOLOCATION & NETWORK INFO (via ip-api.com)
------------------------------------------------
Country:  South Korea (KR)
Region:   Seoul (Guro-gu)
ISP:      Korea Telecom
Org:      AS4766 Korea Telecom
Timezone: Asia/Seoul
------------------------------------------------
```

#### AUTO-DELETE IP
The script can automatically delete IPs that were banned after a certain amount of days has passed
```bash
cf-manage.sh clean <DAYS>
```

#### SCHEDULE AUTO-DELETE IPS
You can also schedule them using a cron:
```bash
(crontab -l 2>/dev/null; echo "0 0 * * * /path/to/cf-manage.sh clean 7 >> /var/log/cf-clean.log 2>&1") | crontab -
```
will delete banned IPs from Cloudflare if they're older than 7 days

## IMPORTANT NOTES
- **REAL IP**: Ensure Nginx domain configs include `include snippets/security-traps.conf;`.
- **NGINX REAL IP HEADER**: Nginx real_ip_header should be enabled and configured. Add this to your `nginx.conf` `http {}` block:
  <details>
  <summary>Cloudflare real_ip configuration (click to expand)</summary>

  ```nginx
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
  </details>
- **CREDENTIALS**: Store Cloudflare credentials in `.env` file (copied from `.env.example`). Never commit `.env` to version control.
- **SSH**: Port 22 is allowed by default.
- **Package Check**: The script automatically skips installation of Nginx, Fail2Ban, etc., if they are already present.
- **Idempotency**: Running `harden.sh` multiple times won't create duplicate UFW rules.