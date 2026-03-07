 Fail2Ban + Nginx + UFW Security Guide 

Fail2Ban + Nginx + UFW Security Hardening Guide
===============================================

Goal
----

This guide configures a hardened web server stack that:

* Monitors `/var/log/nginx/*access.log`
* Detects repeated **403 errors**
* Blocks offending IP addresses using **UFW**
* Detects malicious bots
* Stops WordPress enumeration attacks
* Blocks vulnerability scanners probing `/wp-json/`
* Stops brute force attempts on `/wp-login.php`
* Permanently bans repeat offenders

1\. Install Required Packages
-----------------------------

sudo apt update
sudo apt install fail2ban ufw -y

2\. Enable UFW Firewall
-----------------------

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing

sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'

sudo ufw enable
```

Check status:

```bash
sudo ufw status
```

3\. Configure Fail2Ban to Use UFW
---------------------------------

Create the local jail configuration.

```bash
sudo vim /etc/fail2ban/jail.local
```

Add:

```bash
[DEFAULT]

banaction = ufw
bantime = 1h
findtime = 10m
maxretry = 5

ignoreip = 127.0.0.1/8
```

4\. Create Custom Nginx Protection Jails
----------------------------------------

Create the jail file.

```bash
sudo vim /etc/fail2ban/jail.d/nginx-protection.local
```
```bash
[nginx-403]
enabled = true
filter = nginx-403
port = http,https
logpath = /var/log/nginx/*access.log
maxretry = 10
findtime = 10m
bantime = 1h

[nginx-noscript]
enabled = true
port = http,https
filter = nginx-noscript
logpath = /var/log/nginx/*access.log
maxretry = 6

[nginx-badbots]
enabled = true
port = http,https
filter = nginx-badbots
logpath = /var/log/nginx/*access.log
maxretry = 2

[nginx-limit-req]
enabled = true
port = http,https
filter = nginx-limit-req
logpath = /var/log/nginx/*error.log
maxretry = 5

[nginx-wp-login]
enabled = true
filter = nginx-wp-login
port = http,https
logpath = /var/log/nginx/*access.log
maxretry = 6
findtime = 10m
bantime = 2h

[nginx-wp-json]
enabled = true
filter = nginx-wp-json
port = http,https
logpath = /var/log/nginx/*access.log
maxretry = 4
findtime = 10m
bantime = 1h
```

5\. Create Custom Filters
-------------------------

### 403 Scanner Detection

```bash
sudo vim /etc/fail2ban/filter.d/nginx-403.conf
```

```bash
[Definition]
failregex = ^ .\* "(GET|POST).*" 403
ignoreregex =
```

* * *

### WordPress Login Bruteforce

```bash
sudo vim /etc/fail2ban/filter.d/nginx-wp-login.conf
```
```bash
[Definition]
failregex = ^ .\* "(POST|GET) /wp-login.php.*" (200|403|404)
ignoreregex =
```

* * *

### WordPress JSON Enumeration

```bash
sudo vim /etc/fail2ban/filter.d/nginx-wp-json.conf
```
```bash
[Definition]
failregex = ^ .\* "(GET|POST) /wp-json/.*"
ignoreregex =
```

6\. Permanent Bans for Repeat Offenders (Recidive Jail)
-------------------------------------------------------

Create the configuration:

```bash
sudo vim /etc/fail2ban/jail.d/recidive.local
```
```bash
[recidive]

enabled = true
filter = recidive
logpath = /var/log/fail2ban.log
bantime = 1w
findtime = 1d
maxretry = 5
```

This jail permanently bans IPs that repeatedly trigger Fail2Ban.

7\. Restart Services
--------------------

```bash
sudo systemctl restart fail2ban
sudo systemctl enable fail2ban
```

Check status:

```bash
sudo systemctl status fail2ban
```

8\. Verify Active Jails
-----------------------

```bash
sudo fail2ban-client status
```

Expected output should include:

* nginx-403
* nginx-badbots
* nginx-noscript
* nginx-limit-req
* nginx-wp-login
* nginx-wp-json
* recidive

9\. Testing Fail2Ban
--------------------

### Trigger a 403 Ban

Run repeatedly from a test machine:

```bash
for i in {1..100}; do
curl -I https://yourdomain.com/admin
done
```

After enough attempts, check:

```bash
sudo fail2ban-client status nginx-403
```

10\. Confirm Firewall Blocking
------------------------------

Check blocked IPs:

```bash
sudo ufw status numbered
```

You should see rules similar to:

```bash
DENY IN 192.168.1.10
```

11\. Debugging Fail2Ban
-----------------------

Check logs:

```bash
sudo tail -f /var/log/fail2ban.log
```

Test filters manually:

```bash
sudo fail2ban-regex /var/log/nginx/access.log /etc/fail2ban/filter.d/nginx-403.conf
```

Check a jail:

```bash
sudo fail2ban-client status nginx-403
```

Unban IP:

```bash
sudo fail2ban-client set nginx-403 unbanip 1.2.3.4
```

12\. Security Result
--------------------

This setup protects your server from:

* Directory scanners
* Vulnerability scanners
* WordPress enumeration
* WordPress login brute force
* Bad bots
* Script injection attempts
* Repeat attackers

13\. Block Sensitive File Probing
---------------------------------

Attackers commonly scan for exposed secrets like:

* .env
* .git
* .aws
* .DS_Store
* composer.json
* database backups

These probes are almost always malicious.

### Create Filter

```bash
sudo vim /etc/fail2ban/filter.d/nginx-sensitive-files.conf
```
```bash
[Definition]

failregex = ^ .\* "(GET|POST).*\\.env.*
            ^ .\* "(GET|POST).*\\.git.*
            ^ .\* "(GET|POST).*\\.aws.*
            ^ .\* "(GET|POST).*\\.DS_Store.*
            ^ .\* "(GET|POST).\*composer\\.json.\*
            ^ .\* "(GET|POST).\*backup.\*
            ^ .\* "(GET|POST).\*database.\*

ignoreregex = 
```

### Add Jail

Edit:
```bash
sudo vim /etc/fail2ban/jail.d/nginx-protection.local
```

Add:
```bash
[nginx-sensitive-files]

enabled = true
port = http,https
filter = nginx-sensitive-files
logpath = /var/log/nginx/*access.log
maxretry = 1
bantime = 24h
```

Any probe for these files results in an immediate ban.

14\. Nginx Honeypot Trap
------------------------

A honeypot endpoint is a fake URL that no legitimate user should access. Bots and scanners will hit it almost instantly.

### Create Honeypot Endpoint

Edit your Nginx site configuration:

```bash
sudo vim /etc/nginx/sites-enabled/default
```

Add inside the server block:

```bash
location /wp-admin/install.php {

    access_log /var/log/nginx/honeypot.log;
    return 444;

}
```

Explanation:

* Real WordPress installs never access this page after installation
* Attack scanners probe it frequently
* Nginx returns `444` (connection closed)

Reload Nginx:

```bash
sudo systemctl reload nginx
```

### Create Fail2Ban Filter

```bash
sudo vim /etc/fail2ban/filter.d/nginx-honeypot.conf
```
```bash
[Definition]

failregex = ^ .\* "(GET|POST) /wp-admin/install.php.*

ignoreregex =
```

### Create Jail

```bash
sudo vim /etc/fail2ban/jail.d/nginx-honeypot.local
```
```bash
[nginx-honeypot]

enabled = true
port = http,https
filter = nginx-honeypot
logpath = /var/log/nginx/*access.log
maxretry = 1
bantime = 48h
```

Any bot touching the honeypot gets banned immediately.

15\. Nginx Rate Limiting Integrated with Fail2Ban
-------------------------------------------------

Rate limiting slows brute force attacks and triggers Fail2Ban bans.

### Add Rate Limit Zone

Edit:
```bash
sudo vim /etc/nginx/nginx.conf
```
Inside the `http` block add:
```bash
limit\_req\_zone $binary\_remote\_addr zone=loginlimit:10m rate=5r/m;
```
### Protect WordPress Login

In your site config:
```bash
location = /wp-login.php {

    limit_req zone=loginlimit burst=10 nodelay;

    include fastcgi_params;
    fastcgi_pass php;
}
```
When limits are exceeded Nginx logs errors like:
```bash
limiting requests, excess: 10.000 by zone "loginlimit"
```
Fail2Ban's \*\*nginx-limit-req jail\*\* will detect these and ban the IP. Reload Nginx:
```bash
sudo systemctl reload nginx
```
16\. Testing the Advanced Protections
-------------------------------------

### Test Sensitive File Ban

From another machine run:
```bash
curl http://yourdomain.com/.env
```
Check Fail2Ban:
```bash
sudo fail2ban-client status nginx-sensitive-files
```
17\. Test Honeypot Ban
----------------------

Run:
```bash
curl http://yourdomain.com/wp-admin/install.php
```
Check jail:
```bash
sudo fail2ban-client status nginx-honeypot
```
18\. Test Rate Limit Ban
------------------------

Send rapid requests:
```bash
for i in {1..50}; do
curl http://yourdomain.com/wp-login.php
done
```
Check:
```bash
sudo fail2ban-client status nginx-limit-req
```
19\. Final Security Coverage
----------------------------

With these additions the server automatically blocks:

* Vulnerability scanners
* WordPress enumeration
* WordPress brute force attacks
* Bad bots
* Sensitive file probes
* Reconnaissance scanners
* Rate-limit abuse
* Repeat offenders

This setup dramatically reduces automated attack traffic on public web servers.