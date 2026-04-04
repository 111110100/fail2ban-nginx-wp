# PROJECT MANDATES: NGINX HARDENING & FAIL2BAN

This project manages a high-performance security stack combining Nginx, Fail2Ban, UFW, and Cloudflare. Adhere to these mandates for all modifications:

## 1. TECHNICAL INTEGRITY
- **Real IP First**: Any change to Nginx or Fail2Ban must ensure the `CF-Connecting-IP` header is correctly processed. Never assume the logged IP is the real visitor IP without verifying Nginx `real_ip` configuration.
- **Filter Validation**: After modifying any Fail2Ban filter in `filter.d/`, you MUST run `./fail2ban-test.sh` to verify the regex matches expected patterns.
- **Atomic Actions**: When adding new jails, always ensure they trigger both local (UFW) and global (Cloudflare) actions unless specifically requested otherwise.

## 2. SECURITY STANDARDS
- **Credential Safety**: Never hardcode `CF_ACCOUNT_ID` or `CF_API_TOKEN`. Use the variables in `harden.sh` and ensure they are populated from secure sources or user input.
- **Whitelisting**: Always maintain the Cloudflare IP whitelist in UFW to prevent blocking the edge network itself.

## 3. WORKFLOWS
- **Research**: Before fixing a "failed ban" report, check `/var/log/fail2ban.log` to see if the IP was ignored due to `ignoreip` settings.
- **Testing**: Use `fail2ban-regex` to test new log patterns against existing filters before implementation.
