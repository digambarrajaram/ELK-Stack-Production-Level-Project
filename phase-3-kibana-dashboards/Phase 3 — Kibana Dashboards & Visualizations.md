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

### 📊 Panel 1: Total Requests (Metric)

1. Select visualization type: **Metric**
2. Index pattern: `nginx-access-*`
3. Primary Metric: **`Count`**
4. Global Filter Context: Set the top dashboard time range picker to **Last 24 Hours**.
5. Title configuration: `"Total Requests (24h)"`

**KQL equivalent:**
```kql
*
```

---

### 📈 Panel 2: Request Rate Over Time (Line Chart)

1. Visualization type: **Line** (Lens)
2. **Horizontal Axis (X-axis):** 
   * Field selection: `@timestamp`
   * Function: **`Date histogram`** (Set minimum interval to **`Auto`**)
   * Custom axis title: `Time`
3. **Vertical Axis (Y-axis):** 
   * Function: **`Count`** (Leave target field empty)
   * Custom axis title: `Request Count`
4. **Break down by:** 
   * Field selection: **`status_category.keyword`**
   * Function: **`Top values`** (Set slider or input limit to **`5`**)
5. Title configuration: `"Request Rate by Status Category"`

---

### 🍩 Panel 3: HTTP Status Code Breakdown (Donut)

1. Visualization type: **Donut**
2. **Slice by (Dimensions/Partition):** 
   * Field selection: **`http_status_code`**
   * Function: **`Top values`** (Set maximum value limits to **`10`**)
3. **Size by (Metric Value):** **`Count`**
4. **Filter Bar / KQL Filter:** Add this constraint block directly inside the visualization layer or global search bar to isolate client and server faults:
   ```kql
   http_status_code >= 400
   ```
5. Title configuration: `"HTTP Status Codes"`

---

### 📋 Panel 4: Top Requested Endpoints (Data Table)

1. Visualization type: **Table**
2. **Rows Container (Columns Definition):**
   * Field selection: **`url_path.keyword`**
   * Configuration options: Change row display property limit from default to **`Top 20`**
   * Custom column label: `Endpoint / URL`
3. **Metrics Columns Container:**
   * **Column 1 Metric:** **`Count`** ➔ Custom column label: `Total Requests`
   * **Column 2 Metric:** **`Unique count`** ➔ Field selection: **`client_ip.keyword`** ➔ Custom column label: `Unique Visitors`
4. **Table Sorting:** Click directly on the `Total Requests` column header text inside the central table preview canvas to force sorting order to **Descending** (downward arrow).
5. Title configuration: `"Top Requested Endpoints"`

---

### 🗺️ Panel 5: Geographic Traffic Map

1. Visualization type: **Maps** (Accessed from the Kibana main sidebar menu: **Analytics ➔ Maps**)
2. Click **Add layer** and select source option: **`Documents`**
3. Select Index source pattern: **`nginx-access-*`**
4. Geospatial coordinate field: **`geoip.location`**
5. **Layer Style Formatting:** 
   * Select icon representation: **`Proportional dots`**
   * Select scaling parameter rule: **`Sized by count`**
6. Title configuration: `"Visitor Geographic Distribution"`

---

### 📊 Panel 6: Top Client IPs (Horizontal Bar)

1. Visualization type: **Bar horizontal**
2. **Vertical Axis (Y-axis Dimension):** 
   * Field selection: **`client_ip.keyword`**
   * Function: **`Top values`** (Set length parameter limit to **`10`**)
   * Custom axis title: `Client IP Address`
3. **Horizontal Axis (X-axis Metric):** 
   * Function: **`Count`** (Leave target field empty)
   * Custom axis title: `Total Requests Ingested`
4. Title configuration: `"Top Client IPs"`

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
## Step 4 — Security Events Dashboard

### 📉 Panel 1: Failed SSH Logins Over Time

1. Visualization type: **Area**
2. Index pattern: `syslog-*`
3. **Layer / Global Filter:**
   ```kql
   tags : "ssh_failed_login"
   ```
4. **Horizontal Axis (X-axis):** `@timestamp` (Function: **`Date histogram`**)
5. **Vertical Axis (Y-axis):** Function: **`Count`** (Custom Label: `Failed Attempts`)
6. Title configuration: `"SSH Failed Login Attempts"`

---

### 📋 Panel 2: SSH Attack Source IPs (Table)

1. Visualization type: **Table**
2. Index pattern: `syslog-*`
3. **Layer / Global Filter:**
   ```kql
   tags : "ssh_failed_login"
   ```
4. **Rows Container (Columns Definition):**
   * Field selection: **`ssh_source_ip.keyword`**
   * Configuration options: Change row display property limit to **`Top 20`**
   * Custom column label: `Attacker IP Address`
5. **Metrics Columns Container:** Add two distinct calculation columns:
   * **Column 1 Metric:** **`Count`** ➔ Custom column label: `Total Attacks`
   * **Column 2 Metric:** **`Unique count`** ➔ Field selection: **`ssh_failed_user.keyword`** ➔ Custom column label: `Unique Users Targeted`
6. **Table Sorting:** Click directly on the `Total Attacks` column header text inside your data grid preview to force the sorting hierarchy order to **Descending** (downward arrow).
7. Title configuration: `"Top SSH Attack Sources"`
---

---

### 🔍 Panel 3: Security Event Timeline (Discover Workspace)

Use the dedicated **Discover Interface** (not a static dashboard widget) to perform deep-dive forensic investigation and active incident triage.

#### 🛠️ Workspace Preparation Step
1. Navigate to **Analytics ➔ Discover**.
2. Set the top-left Data View dropdown selection pattern to: **`syslog-*`**.
3. Under the **Available fields** list in the left sidebar, click the **`+` (plus sign)** next to these specific parameters to structure them as tabular data columns:
   * `syslog_program`
   * `ssh_source_ip`
   * `ssh_failed_user`
   * `tags`

#### 🧪 Target Forensic Investigations
Execute these queries by pasting them directly into the main top **`Search (KQL)...`** bar, pressing **Enter**, and clicking **Save** in the top right to log them into corporate operational memory:

*   **Investigation 1: All Security Events**
    *   *KQL Syntax String:* 
        ```kql
        tags : "ssh_failed_login" OR tags : "ssh_success" OR tags : "oom_event"
        ```
    *   *Saved Object Title Name:* `security_event_timeline_all`
*   **Investigation 2: Automated Brute-Force Vectoring**
    *   *KQL Syntax String:* 
        ```kql
        tags : "ssh_failed_login" AND ssh_source_ip : *
        ```
    *   *Saved Object Title Name:* `security_event_timeline_brute_force`
*   **Investigation 3: Core Node Resource Exhaustions**
    *   *KQL Syntax String:* 
        ```kql
        tags : "disk_full" OR tags : "oom_event"
        ```
    *   *Saved Object Title Name:* `security_event_timeline_system_health`

---

## Step 5 — Export Dashboards (for GitHub Version Control)

Export dashboard objects as NDJSON files to establish Git-backed tracking infrastructure configuration history and backup rollbacks.

### 🎛️ Option A: Via Kibana Saved Objects User Interface
1. Navigate to **Management ➔ Stack Management ➔ Saved Objects**.
2. Click the **Type** filter selection dropdown and check **Dashboard**.
3. Click the checkboxes next to your customized metrics panels.
4. Click **Export** in the top action header bar and ensure **Include references** is toggled **ON**.
5. Save the resulting `.ndjson` package tracking component asset array into your deployment repository pathway: `phase-3-kibana-dashboards/dashboards/`

### 🖥️ Option B: Via Command-Line Interface (REST API Integration)
Run these commands within your administrative control host to automate backup states or deploy layouts to newly instantiated nodes:

```bash
# 1. Query the cluster database to extract explicit Dashboard ID parameters
curl -X GET "http://localhost:5601/api/saved_objects/_find?type=dashboard&per_page=20" \
  -H "kbn-xsrf: true" | python3 -m json.tool

# 2. Export targeted analytics dashboards directly to your local file path
curl -X GET "http://localhost:5601/api/kibana/dashboards/export?dashboard=<YOUR_EXTRACTED_DASHBOARD_ID>" \
  -H "kbn-xsrf: true" \
  -o phase-3-kibana-dashboards/dashboards/all-dashboards.ndjson

# 3. Import saved configuration schema models onto clean target environments
curl -X POST "http://localhost:5601/api/saved_objects/_import?createNewCopies=true" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: multipart/form-data" \
  --form file=@phase-3-kibana-dashboards/dashboards/all-dashboards.ndjson
```

---

## Step 6 — Useful KQL Queries Reference

Save this centralized verification lookup guide as a file inside your repository path: `dashboards/kql-cheatsheet.md`.

```kql
# ── Nginx Web Traffic Analytics ─────────────────────
# Isolate complete 5xx Application Server faults
http_status_code >= 500

# Audit authorization credential issues on targeted entry paths
url_path.keyword : "/api/v1/auth/login" AND http_status_code : 401

# Track traffic frequency vectors originating from a single source host
client_ip.keyword : "192.168.12.4"

# Filter transaction traffic metrics by specific geographic regions
geoip.country_name : "India"

# ── Microservice Application Reliability ────────────
# Filter system log streams for application errors or panics
log_level : "ERROR" OR log_level : "FATAL"

# Trace slow queries or processing delays exceeding service thresholds
response_time_ms > 2000

# Isolate critical runtime errors impacting a specific system component
service_name : "payment-api" AND log_level : "ERROR"

# ── Infrastructure Security & Auditing ─────────────
# Track brute-force network connection failures
tags : "ssh_failed_login"

# Monitor and verify administrative session access requests
tags : "ssh_success"

# Audit node kernel out-of-memory container terminations
tags : "oom_event"

# ── Cross-Layer Multi-Incident Correlation ──────────
# Filter for platform critical system crashes and active attacks
log_level : "FATAL" OR tags : "ssh_failed_login" OR tags : "disk_full"

# Isolate sliding window incidents occurring within the last 15 minutes
@timestamp > now-15m AND (log_level : "ERROR" OR http_status_code >= 500)
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
