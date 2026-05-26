# Phase 3 — Kibana Dashboards & Visualizations

> **Goal:** Build 4 production-quality Kibana dashboards — Infrastructure Health, Nginx Analytics, Application Performance, and Security Events. These are your portfolio screenshots.  
> **Time estimate:** 3–4 hours  
> **What you'll learn:** Kibana Lens, TSVB, Discover, KQL, Dashboard export/import, Maps, Visualizations

---

## 📐 Dashboards We'll Build

| Dashboard | Index | Key Panels | Status |
|-----------|-------|------------|--------|
| Nginx Analytics | `nginx-access-*` | Request rate, Status breakdown, Top URLs, GeoIP map | ⭐ 6 panels |
| Application Performance | `app-logs-*` | Error rate, Response time P95, Slow requests, Service breakdown | ⭐ 5 panels |
| Security Events | `syslog-*` | SSH failed logins, Source IP map, Login timeline | ⭐ 3 panels |
| Infrastructure Health | All | Event volume, Error trends, Top log sources | ⭐ 4 panels |

---

## Step 0 — Prerequisites

### Create Data Views in Kibana

Before building dashboards, create index patterns (called "Data Views" in 8.x+):

1. Open Kibana: `http://<EC2_IP>:5601`
2. Click **Stack Management** (⚙️ icon, bottom left)
3. Under **Kibana**, click **Data Views**
4. Click **Create data view**

Create these three data views:

| Name | Index Pattern | Timestamp Field |
|------|---------------|-----------------|
| nginx-access | `nginx-access-*` | `@timestamp` |
| app-logs | `app-logs-*` | `@timestamp` |
| syslog | `syslog-*` | `@timestamp` |

Click **Create** for each. Data views are now ready!

---

## Step 1 — Create Nginx Analytics Dashboard

### 1.1 Navigate to Dashboards

1. Click **Analytics** (left sidebar)
2. Click **Dashboards**
3. Click **Create dashboard** (top right)
4. Click **Create visualization**

---

### 1.2 Panel 1: Total Requests (Metric)

**Configuration:**
- Data View: `nginx-access`
- Visualization type: **Metric**
- Metric: `Count`
- Time filter: **Last 24 hours**

**Steps:**
1. Select visualization type: **Metric**
2. Select data view: `nginx-access`
3. Keep default count aggregation
4. Title: `"Total Requests (24h)"`
5. Click **Save** (don't add to dashboard yet)

---

### 1.3 Panel 2: Request Rate Over Time (Line Chart)

**Configuration:**
- Data View: `nginx-access`
- X-axis: `@timestamp` (Date histogram)
- Y-axis: `Count`
- Break down by: `status_category.keyword`

**Steps:**
1. Visualization type: **Line** (Lens)
2. Data view: `nginx-access`
3. Configure:
   - **Horizontal Axis:** `@timestamp` → Date histogram
   - **Vertical Axis:** Count (default)
   - **Break down by:** `status_category.keyword` → Top values (limit 5)
4. Title: `"Request Rate by Status Category"`
5. Click **Save**

---

### 1.4 Panel 3: HTTP Status Code Distribution (Donut)

**Configuration:**
- Data View: `nginx-access`
- Slice by: `http_status_code`
- Filter: `http_status_code >= 400`

**Steps:**
1. Visualization type: **Donut**
2. Data view: `nginx-access`
3. Configure:
   - **Slice by:** `http_status_code` → Top values (10)
   - **Size by:** Count
4. Add filter: `http_status_code >= 400`
5. Title: `"HTTP Status Codes (4xx/5xx)"`
6. Click **Save**

---

### 1.5 Panel 4: Top Requested Endpoints (Table)

**Configuration:**
- Data View: `nginx-access`
- Rows: `url_path.keyword`
- Metrics: Count, Unique IPs

**Steps:**
1. Visualization type: **Table**
2. Data view: `nginx-access`
3. Configure:
   - **Rows:** `url_path.keyword` → Top 20
   - **Column 1:** Count → Label: "Total Requests"
   - **Column 2:** Unique count of `client_ip.keyword` → Label: "Unique Visitors"
4. Sort by "Total Requests" descending
5. Title: `"Top Requested Endpoints"`
6. Click **Save**

---

### 1.6 Panel 5: Geographic Traffic Map

**Configuration:**
- Data View: `nginx-access`
- Layer: Documents
- Location field: `geoip.location`

**Steps:**
1. Visualization type: **Maps**
2. Data view: `nginx-access`
3. Add layer → Documents
4. Configure:
   - **Index pattern:** `nginx-access`
   - **Geospatial field:** `geoip.location`
   - **Styling:** Proportional dots, sized by count
5. Title: `"Visitor Geographic Distribution"`
6. Click **Save**

---

### 1.7 Panel 6: Top Client IPs (Horizontal Bar)

**Configuration:**
- Data View: `nginx-access`
- Y-axis: `client_ip.keyword` (Top 10)
- X-axis: Count

**Steps:**
1. Visualization type: **Bar (horizontal)**
2. Data view: `nginx-access`
3. Configure:
   - **Y-axis (Dimension):** `client_ip.keyword` → Top values (10)
   - **X-axis (Metric):** Count
4. Title: `"Top Client IPs"`
5. Click **Save**

---

### 1.8 Assemble Dashboard

1. Click **Dashboards** → Your new dashboard
2. Click **Edit**
3. Drag panels to arrange:

```
┌─────────────────┬────────────────┬────────────────┐
│ Total Requests  │  Total 4xx/5xx │  Avg Response  │
│    (Metric)     │    (Metric)    │    (Metric)    │
├─────────────────┴────────────────┴────────────────┤
│           Request Rate Over Time (Line)           │
├───────────────────────┬───────────────────────────┤
│  Status Breakdown     │     Top URLs (Table)      │
│    (Donut)            │                           │
├───────────────────────┴───────────────────────────┤
│        Geographic Distribution (Map)              │
├───────────────────────────────────────────────────┤
│           Top Client IPs (Bar)                    │
└───────────────────────────────────────────────────┘
```

Click **Save** → Name: `"Nginx Analytics Dashboard"`

---

## Step 2 — Create Application Performance Dashboard

### 2.1 Panel 1: Total Errors (Metric)

**Steps:**
1. Create visualization → **Metric**
2. Data view: `app-logs`
3. Add filter: `log_level: ("ERROR" OR "FATAL")`
4. Title: `"Total Errors"`
5. Save

---

### 2.2 Panel 2: Error Rate Over Time (Area Chart)

**Steps:**
1. Visualization type: **Area** (Lens)
2. Data view: `app-logs`
3. Configure:
   - **X-axis:** `@timestamp` → Date histogram
   - **Y-axis:** Count
   - **Break down by:** `log_level.keyword`
4. Filter: `log_level: ("ERROR" OR "FATAL")`
5. Title: `"Error Rate Over Time"`
6. Save

---

### 2.3 Panel 3: Response Time P95 (Metric)

**Steps:**
1. Visualization type: **Metric**
2. Data view: `app-logs`
3. Configure:
   - **Aggregation:** Percentile of `response_time_ms`
   - **Percentile:** 95
4. Title: `"P95 Response Time (ms)"`
5. Save

---

### 2.4 Panel 4: Slow Requests (Table)

**Steps:**
1. Visualization type: **Table**
2. Data view: `app-logs`
3. Filter: `response_time_ms > 1000`
4. Configure:
   - **Row:** `service_name.keyword`
   - **Columns:** 
     - Count → "Slow Requests"
     - Percentile of response_time_ms → "P95 Time (ms)"
5. Title: `"Services with Slow Requests"`
6. Save

---

### 2.5 Panel 5: Error by Service (Vertical Bar)

**Steps:**
1. Visualization type: **Bar** (vertical)
2. Data view: `app-logs`
3. Configure:
   - **X-axis:** `service_name.keyword` → Top 10
   - **Y-axis:** Count
4. Filter: `log_level: "ERROR"`
5. Title: `"Errors by Service"`
6. Save

---

### 2.6 Assemble Application Dashboard

Name: `"Application Performance Dashboard"`

Layout:
```
┌──────────────┬──────────────┬──────────────┐
│Total Errors  │ Error Rate   │  P95 Response│
│  (Metric)    │ (Metric)     │   (Metric)   │
├──────────────┴──────────────┴──────────────┤
│         Error Rate Over Time (Area)        │
├──────────────────┬─────────────────────────┤
│ Errors by Service│  Slow Requests (Table)  │
│    (Bar)         │                         │
└──────────────────┴─────────────────────────┘
```

---

## Step 3 — Create Security Events Dashboard

### 3.1 Panel 1: SSH Failed Login Attempts (Area)

**Steps:**
1. Visualization type: **Area**
2. Data view: `syslog`
3. Configure:
   - **X-axis:** `@timestamp`
   - **Y-axis:** Count
4. Filter: `tags: "ssh_failed_login"`
5. Title: `"SSH Failed Login Attempts"`
6. Save

---

### 3.2 Panel 2: Top SSH Attack Sources (Table)

**Steps:**
1. Visualization type: **Table**
2. Data view: `syslog`
3. Filter: `tags: "ssh_failed_login"`
4. Configure:
   - **Row:** `ssh_source_ip.keyword` → Top 20
   - **Columns:**
     - Count → "Total Attempts"
     - Unique count of `ssh_failed_user.keyword` → "Unique Users Targeted"
5. Title: `"Top SSH Attack Sources"`
6. Save

---

### 3.3 Panel 3: Security Event Timeline (Discover)

Save as saved object in Discover:

**Steps:**
1. Navigate to **Discover**
2. Data view: `syslog`
3. KQL: `tags: ("ssh_failed_login" OR "ssh_success" OR "disk_full" OR "oom_event")`
4. Add columns:
   - `syslog_program`
   - `ssh_source_ip`
   - `security_event`
   - `tags`
5. Click **Save** → Name: `"security_event_timeline"`

---

### 3.4 Assemble Security Dashboard

Name: `"Security Events Dashboard"`

Layout:
```
┌──────────────────────────────────────┐
│  SSH Failed Login Attempts (Area)    │
├──────────────────────────────────────┤
│   Top SSH Attack Sources (Table)     │
├──────────────────────────────────────┤
│ Security Event Timeline (Saved Obj)  │
└──────────────────────────────────────┘
```

---

## Step 4 - 🧪 Target Forensic Investigations
Execute these queries by pasting them directly into the main top **`Search (KQL)...`** bar, pressing **Enter**, and clicking **Save** in the top right to log them into corporate operational memory:

### 4.1 **Investigation: All Security Events**

KQL Syntax String:
```kql
tags : "ssh_failed_login" OR tags : "ssh_success" OR tags : "oom_event"
```
Saved Object Title Name: `security_event_timeline_all`


---
### 4.2 **Investigation 2: Automated Brute-Force Vectoring**

KQL Syntax String:
```kql
tags : "ssh_failed_login" AND ssh_source_ip : *
```
Saved Object Title Name: `security_event_timeline_brute_force`


---
### 4.3 **Investigation 3: Core Node Resource Exhaustions**
        
KQL Syntax String:
```kql
tags : "disk_full" OR tags : "oom_event"
```
Saved Object Title Name: `security_event_timeline_system_health`

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
