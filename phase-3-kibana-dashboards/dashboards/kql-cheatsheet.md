```kql
# ── Nginx ──────────────────────────────────────────
# All 5xx errors
http_status_code >= 500

# Specific endpoint errors
url_path: "/api/login" AND http_status_code: 401

# High traffic from single IP (potential DDoS)
client_ip: "1.2.3.4"

# Requests from specific country
geoip.country_name: "Russia"

# ── Application ────────────────────────────────────
# All errors
log_level: ERROR OR log_level: FATAL

# Slow requests with trace IDs
response_time_ms > 2000

# Specific service errors
service_name: "payment-service" AND log_level: ERROR

# ── Security ───────────────────────────────────────
# Failed SSH logins
security_event: "ssh_failed_login"

# Successful logins (verify legitimacy)
security_event: "ssh_success"

# OOM events
system_event: "oom_kill"

# ── Combined ───────────────────────────────────────
# Everything critical
log_level: FATAL OR tags: "ssh_failed_login" OR tags: "disk_full"

# Last 15 minutes errors
@timestamp > now-15m AND (log_level: ERROR OR http_status_code >= 500)
```