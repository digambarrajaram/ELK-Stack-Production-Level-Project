# Phase 3 — Kibana Dashboards & Visualizations

> **Goal:** Build 4 production-quality Kibana dashboards — Infrastructure Health, Nginx Analytics, Application Performance, and Security Events. These are your portfolio screenshots.  
> **Time estimate:** 3–4 hours  
> **What you'll learn:** Kibana Lens, TSVB, Discover, KQL, Dashboard export/import, Maps

---

## 📐 Dashboards We'll Build

| Dashboard | Index | Key Panels |
|-----------|-------|------------|
| Nginx Analytics | `nginx-access-*` | Request rate, Status breakdown, Top URLs, GeoIP map |
| Application Performance | `app-logs-*` | Error rate, Response time P95, Slow requests, Service breakdown |
| Security Events | `syslog-*` | SSH failed logins, Source IP map, Login timeline |
| Infrastructure Health | All | Event volume, Error trends, Top log sources |

---

## Step 1 — Create Index Patterns

Before building dashboards, Kibana needs index patterns to know your data.

1. Go to **Stack Management** (gear icon, bottom-left)
2. Click **Index Patterns** → **Create index pattern**

Create these three:

| Index Pattern | Time Field |
|---------------|-----------|
| `nginx-access-*` | `@timestamp` |
| `app-logs-*` | `@timestamp` |
| `syslog-*` | `@timestamp` |

---

## Step 2 — Nginx Analytics Dashboard

### Navigate to Dashboard
**Analytics → Dashboards → Create dashboard → Create visualization**

---

### Panel 1: Total Requests (Metric)

1. Select visualization type: **Metric**
2. Index: `nginx-access-*`
3. Metric: `Count`
4. Add filter: last 24 hours
5. Title: "Total Requests (24h)"

**KQL equivalent:**
```kql
*
```

---

### Panel 2: Request Rate Over Time (Line Chart)

1. Visualization type: **Line** (Lens)
2. X-axis: `@timestamp` (Date histogram, auto interval)
3. Y-axis: `Count` (records)
4. Break down by: `status_category` (Top 5 values)
5. Title: "Request Rate by Status Category"

---

### Panel 3: HTTP Status Code Breakdown (Donut)

1. Visualization type: **Donut**
2. Slice by: `http_status_code` (Top 10 values)
3. Size by: `Count`
4. Title: "HTTP Status Codes"

Add a filter to highlight errors:
```kql
http_status_code >= 400
```

---

### Panel 4: Top Requested URLs (Data Table)

1. Visualization type: **Table**
2. Rows: `url_path` (Top 20 values)
3. Metrics columns: `Count`, `Unique client_ip count`
4. Sort by: Count descending
5. Title: "Top Requested Endpoints"

---

### Panel 5: Geographic Traffic Map

1. Visualization type: **Maps** (from main menu: Analytics → Maps)
2. Add layer: **Documents** from `nginx-access-*`
3. Geospatial field: `geoip.location`
4. Style: Proportional dots, sized by count
5. Title: "Visitor Geographic Distribution"

---

### Panel 6: Top Client IPs (Horizontal Bar)

1. Visualization type: **Bar horizontal**
2. Y-axis: `client_ip` (Top 10)
3. X-axis: `Count`
4. Title: "Top Client IPs"

---

### Assemble the Dashboard

Arrange panels like this:

```
┌─────────────────┬────────────────┬────────────────┐
│  Total Requests │  Total Errors  │  Avg Response  │
│     (Metric)    │    (Metric)    │    (Metric)    │
├─────────────────┴────────────────┴────────────────┤
│           Request Rate Over Time (Line)           │
├───────────────────────┬───────────────────────────┤
│   Status Breakdown    │     Top URLs (Table)      │
│      (Donut)          │                           │
├───────────────────────┴───────────────────────────┤
│             GeoIP Map (full width)                │
└───────────────────────────────────────────────────┘
```

**Save as:** "Nginx Analytics Dashboard"

---

## Step 3 — Application Performance Dashboard

### Panel 1: Error Rate % (Gauge)

1. Visualization type: **Gauge**
2. Formula: `count(kql='log_level: ERROR') / count() * 100`
3. Color ranges: 0–5 green, 5–10 yellow, 10+ red
4. Title: "Error Rate %"

---

### Panel 2: Response Time Percentiles (Line)

1. Visualization type: **Line** (Lens)
2. X-axis: `@timestamp`
3. Y-axis (multiple):
   - `Percentile(response_time_ms, 50)` — label: P50
   - `Percentile(response_time_ms, 95)` — label: P95
   - `Percentile(response_time_ms, 99)` — label: P99
4. Title: "Response Time Percentiles (ms)"

> **Why P95/P99 matters in interviews:** "P95 response time" means 95% of requests complete within that time. Employers love this — it's how SLOs are defined.

---

### Panel 3: Errors by Service (Stacked Bar)

1. Visualization type: **Bar vertical stacked**
2. X-axis: `@timestamp` (Date histogram)
3. Y-axis: `Count`
4. Break down by: `service_name`
5. Filter: `log_level: ERROR OR log_level: FATAL`
6. Title: "Errors by Service Over Time"

---

### Panel 4: Slow Requests Table

1. Visualization type: **Table**
2. Filter: `tags: "slow_request"`
3. Columns: `@timestamp`, `service_name`, `trace_id`, `response_time_ms`, `log_message`
4. Sort: `response_time_ms` descending
5. Title: "Slow Requests (>1000ms)"

---

### Panel 5: Log Level Distribution (Pie)

1. Visualization type: **Pie**
2. Slice by: `log_level` (Top 5)
3. Size by: `Count`
4. Title: "Log Level Distribution"

---

## Step 4 — Security Events Dashboard

### Panel 1: Failed SSH Logins Over Time

1. Visualization type: **Area**
2. Filter: `tags: "ssh_failed_login"`
3. X-axis: `@timestamp`
4. Y-axis: `Count`
5. Title: "SSH Failed Login Attempts"

---

### Panel 2: SSH Attack Source IPs (Table)

1. Visualization type: **Table**
2. Filter: `tags: "ssh_failed_login"`
3. Rows: `ssh_source_ip` (Top 20)
4. Metrics: `Count`, `Unique ssh_failed_user count`
5. Sort: Count descending
6. Title: "Top SSH Attack Sources"

---

### Panel 3: Security Event Timeline (Discover)

Use **Discover** (not a panel) to investigate events:

```kql
# All security events
tags: "ssh_failed_login" OR tags: "ssh_success" OR tags: "oom_event"

# Brute force: >10 failed attempts from same IP
tags: "ssh_failed_login" AND ssh_source_ip: *

# Recent system events
tags: "disk_full" OR tags: "oom_event"
```

---

## Step 5 — Export Dashboards (for GitHub)

Export dashboards as NDJSON so you can version-control and re-import them.

**Via Kibana UI:**
1. Go to **Stack Management → Saved Objects**
2. Filter by Type: Dashboard
3. Select all your dashboards
4. Click **Export** → downloads `.ndjson` file
5. Save to `phase-3-kibana-dashboards/dashboards/`

**Via API:**
```bash
# Export all dashboards
curl -X GET "http://localhost:5601/api/kibana/dashboards/export?dashboard=<dashboard-id>" \
  -H "kbn-xsrf: true" \
  -o dashboards/all-dashboards.ndjson

# List saved objects to find dashboard IDs
curl -X GET "http://localhost:5601/api/saved_objects/_find?type=dashboard&per_page=20" \
  -H "kbn-xsrf: true" | python3 -m json.tool

# Import dashboards on a new instance
curl -X POST "http://localhost:5601/api/kibana/dashboards/import" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -d @dashboards/nginx-analytics.ndjson
```

---

## Step 6 — Useful KQL Queries Reference

Save these in `dashboards/kql-cheatsheet.md` for quick access:

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

---

## ✅ Phase 3 Checklist

- [ ] Index patterns created for all 3 indices
- [ ] Nginx Analytics Dashboard built and saved (6+ panels)
- [ ] Application Performance Dashboard built (5+ panels)
- [ ] Security Events Dashboard built
- [ ] Dashboards exported as `.ndjson` and committed to GitHub
- [ ] KQL queries tested and returning expected results
- [ ] Response time percentile visualization shows P50/P95/P99

---

## 🧠 Concepts You Learned in Phase 3

- **Kibana Lens** is the modern visualization builder — drag-and-drop field-based interface. Knows the difference between metrics, dimensions, and breakdowns.
- **KQL (Kibana Query Language)** is Kibana's filter syntax. More readable than raw Elasticsearch DSL. Uses `:` for field matching, `>` / `<` for ranges, `AND/OR/NOT` for logic.
- **P95 response time** means 95% of requests complete within that threshold — the standard SLO metric.
- **TSVB (Time Series Visual Builder)** is for advanced time-series — rates, moving averages, threshold markers.
- **Saved Objects export/import** is how you version-control dashboards in Git and deploy them to new environments.

---

## ➡️ Next Step

Proceed to **[Phase 4 — Alerting & Anomaly Detection](../phase-4-alerting/README.md)**
