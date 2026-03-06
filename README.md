 Fail2ban + Nginx + UFW WordPress Security Guide

# Fail2ban + Nginx + UFW Security Hardening

This guide configures Fail2ban to automatically block malicious traffic detected in Nginx logs.

## Jails Implemented

*   nginx-403
*   nginx-badbots
*   nginx-noscript
*   nginx-limit-req
*   nginx-wp-login
*   nginx-wp-json
*   recidive (permanent bans)

- - -

## 1 Install Dependencies
```bash
sudo apt update
sudo apt install fail2ban ufw

Verify installation:

fail2ban-client -V
```
- - -

## 2 Configure UFW Firewall

Allow essential services:
```bash
sudo ufw allow ssh
sudo ufw allow http
sudo ufw allow https

Enable firewall:

sudo ufw enable
```
Verify:
```bash
sudo ufw status verbose
```
- - -

## 3 Confirm Nginx Logs

Fail2ban will monitor all access logs:
```bash
/var/log/nginx/\*access.log
```
Error logs:
```bash
/var/log/nginx/error.log
```
Test logging:
```bash
tail -f /var/log/nginx/access.log
```
- - -

## 4 Create Fail2ban Filters

Location:

/etc/fail2ban/filter.d/

\---

### nginx-403
```bash
sudo vim /etc/fail2ban/filter.d/nginx-403.conf
```
#### nginx-403.conf
```bash
[Definition]
failregex = ^ - .\* "(GET|POST|HEAD).\*" 403
ignoreregex =
```
\---

### nginx-badbots
```bash
sudo vim /etc/fail2ban/filter.d/nginx-badbots.conf
```
#### nginx-badbots.conf
```bash
[Definition]
failregex = ^ -.\*"(GET|POST|HEAD).\*HTTP.\*" .\* "(.\*(sqlmap|nikto|masscan|dirbuster|nmap|wpscan).\*)"
ignoreregex =
```
\---

### nginx-noscript
```bash
sudo vim /etc/fail2ban/filter.d/nginx-noscript.conf
```
#### nginx-noscript.conf
```bash
[Definition]
failregex = ^ -.\*"(GET|POST).\*\\/(uploads|files|images)\\/.\*\\.php
ignoreregex =
```

\---

### nginx-limit-req
```bash
sudo vim /etc/fail2ban/filter.d/nginx-limit-req.conf
```
#### nginx-limit-req.conf
```bash
[Definition]
failregex = limiting requests, excess:.\* by zone.\* client:
ignoreregex =
```
\---

### nginx-wp-login

Blocks brute force attacks against WordPress login.
```bash
sudo vim /etc/fail2ban/filter.d/nginx-wp-login.conf
```
#### nginx-wp-login.conf
```bash
[Definition]
failregex = ^ -.\*"(POST|GET).\*wp-login.php
ignoreregex =
```
\---

### nginx-wp-json

Blocks scanners probing WordPress REST API.
```bash
sudo vim /etc/fail2ban/filter.d/nginx-wp-json.conf
```
#### nginx-wp-json.conf
```bash
[Definition]
failregex = ^ -.\*"(GET|POST).\*\\/wp-json\\/.\*
ignoreregex =
```
\---

- - -

## 5 Configure Jails

Create:
```bash
sudo vim /etc/fail2ban/jail.d/nginx-protection.local
```
#### nginx-protection.local
```bash
[nginx-403]
enabled = true
filter = nginx-403
logpath = /var/log/nginx/\*access.log
maxretry = 10
findtime = 60
bantime = 3600
action = ufw


[nginx-badbots]
enabled = true
filter = nginx-badbots
logpath = /var/log/nginx/\*access.log
maxretry = 2
findtime = 3600
bantime = 86400
action = ufw


[nginx-noscript]
enabled = true
filter = nginx-noscript
logpath = /var/log/nginx/\*access.log
maxretry = 2
findtime = 600
bantime = 86400
action = ufw


[nginx-limit-req]
enabled = true
filter = nginx-limit-req
logpath = /var/log/nginx/error.log
maxretry = 10
findtime = 60
bantime = 3600
action = ufw


[nginx-wp-login]
enabled = true
filter = nginx-wp-login
logpath = /var/log/nginx/\*access.log
maxretry = 5
findtime = 300
bantime = 86400
action = ufw


[nginx-wp-json]
enabled = true
filter = nginx-wp-json
logpath = /var/log/nginx/\*access.log
maxretry = 10
findtime = 60
bantime = 86400
action = ufw
```
- - -

## 6 Permanent Bans for Repeat Offenders (Recidive Jail)

This jail monitors the Fail2ban log itself and permanently bans IPs that repeatedly trigger bans. Create:
```bash
sudo vim /etc/fail2ban/jail.d/recidive.local
```
#### recidive.local
```bash
[recidive]

enabled = true
logpath = /var/log/fail2ban.log
banaction = ufw
bantime = -1
findtime = 86400
maxretry = 5
```
Meaning:

*   If an IP is banned 5 times in 24 hours
*   It is permanently banned

- - -

## 7 Restart Fail2ban
```bash
sudo systemctl restart fail2ban
```
Check active jails:
```bash
sudo fail2ban-client status
```
Expected:
```bash
nginx-403
nginx-badbots
nginx-noscript
nginx-limit-req
nginx-wp-login
nginx-wp-json
recidive
```
- - -

## 8 Testing Each Jail

### Test nginx-403
```bash
for i in {1..20}; do
curl http://YOURSERVER/.env
done
```
\---

### Test Bad Bots
```bash
curl -A "sqlmap" http://YOURSERVER
```
\---

### Test PHP Upload Attack
```bash
curl http://YOURSERVER/uploads/shell.php
```
\---

### Test WordPress Login
```bash
for i in {1..10}; do
curl http://YOURSERVER/wp-login.php
done
```
\---

### Test WordPress JSON Scanning
```bash
for i in {1..20}; do
curl http://YOURSERVER/wp-json/wp/v2/users
done
```
\---

### Test Rate Limiting
```bash
ab -n 200 -c 50 http://YOURSERVER/
```
\---

- - -

## 9 Verify Firewall Blocking
```bash
sudo ufw status numbered
```
Example:
```bash
DENY IN 203.0.113.45
```
\---

## 10 View Fail2ban Logs
```bash
sudo tail -f /var/log/fail2ban.log
```
Example:
```bash
Ban 203.0.113.100
```
\---

## 11 Unban an IP
```bash
sudo fail2ban-client set nginx-403 unbanip IPADDRESS
```
Example:
```bash
sudo fail2ban-client set nginx-403 unbanip 192.168.1.100
```
\---

### Recommended Production Hardening

*   Increase bantime to 24–72 hours
*   Whitelist trusted IPs with ignoreip
*   Combine with Nginx rate limiting
*   Monitor logs regularly
