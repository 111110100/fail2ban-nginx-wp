# FAIL2BAN JAIL REFERENCE

| Jail Name | Max Retry | Find Time | Ban Time | Primary Action |
|-----------|-----------|-----------|----------|----------------|
| `nginx-403` | 10 | 600s | 3600s | UFW + Cloudflare |
| `nginx-honeypot` | 1 | 600s | 86400s | UFW + Cloudflare |
| `nginx-scanner` | 1 | 600s | 86400s | UFW + Cloudflare |
| `nginx-sensitive-files` | 1 | 600s | 86400s | UFW + Cloudflare |
| `nginx-ai-scrapers` | 2 | 600s | 86400s | UFW + Cloudflare |
| `nginx-wp-login` | 3 | 3600s | 86400s | UFW + Cloudflare |
| `nginx-wp-cron` | 5 | 600s | 86400s | UFW + CF + Custom Log |
| `nginx-php-probes` | 2 | 600s | 86400s | UFW + Cloudflare |
| `nginx-exploits` | 2 | 3600s | 86400s | UFW + Cloudflare |
| `recidive` | 5 | 86400s | 604800s | UFW + Cloudflare |

## Threshold Logic
- **Soft Jails (`nginx-403`)**: Allow for occasional user error. High thresholds prevent accidental blocking of legitimate users.
- **Hard Jails (`nginx-honeypot`, `nginx-scanner`)**: Ban on first attempt. These target URIs that should NEVER be hit by a real user.
- **Service-Specific Jails (`nginx-wp-*`)**: Balanced thresholds to allow normal platform activity while catching rapid-fire brute-force or abuse.
