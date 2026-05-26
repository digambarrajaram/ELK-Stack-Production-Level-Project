# Phase 4 — Alerting & Anomaly Detection

> **Goal:** Set up ElastAlert2 with real alert rules — spike detection, brute-force detection, error-rate threshold alerts — all wired to email notifications (Gmail SMTP). Then add Elasticsearch Watcher for metric-based alerting.  
> **Time estimate:** 3–4 hours  
> **What you'll learn:** ElastAlert2 rule types, Watcher queries, SMTP/Gmail integration, alert tuning, MTTD concepts
---

## 📐 Alerting Architecture

```
Elasticsearch Indices
        │
        ├──► ElastAlert2 ──► Slack / Email
        │    (scheduled     (notification)
        │     queries)
        │
        └──► Kibana Watcher ──► Slack / Email
             (built-in,          (notification)
              paid feature)
```

> **Note:** ElastAlert2 is open-source and free. Kibana Watcher requires a paid X-Pack license. We primarily use ElastAlert2, and show Watcher as reference.

---

## Step 1 — Add ElastAlert2 to Docker Compose

Add this service to your `docker-compose.yml`:

```yaml
elastalert:
  image: jertel/elastalert2:latest
  container_name: elastalert2

  env_file:
    - .env

  volumes:
    - ./phase-4-alerting/elastalert2/config.yml:/opt/elastalert/config.yml:ro
    - ./phase-4-alerting/elastalert2/rules:/opt/elastalert/rules:ro
    - ./phase-4-alerting/elastalert2/data:/opt/elastalert/data
    - ./phase-4-alerting/elastalert2/smtp_auth.yaml:/opt/elastalert/smtp_auth.yaml:ro

  environment:
    - TZ=Asia/Kolkata

  depends_on:
    elasticsearch:
      condition: service_healthy

  restart: unless-stopped
```

---

## Step 2 — ElastAlert2 Base Config

**`elastalert2/config.yml`**
```yaml
# -------------------------------
# Elasticsearch
# -------------------------------
es_host: elasticsearch
es_port: 9200

# -------------------------------
# ElastAlert Behavior
# -------------------------------
run_every:
  minutes: 1

buffer_time:
  minutes: 15

writeback_index: elastalert_status
writeback_alias: elastalert

alert_time_limit:
  days: 2

use_local_time: true
timezone: Asia/Kolkata

rules_folder: /opt/elastalert/rules

logging_level: INFO

# -------------------------------
# Gmail SMTP
# -------------------------------
smtp_host: ${SMTP_HOST}
smtp_port: ${SMTP_PORT}
smtp_auth_file: /opt/elastalert/smtp_auth.yaml

from_addr: ${ALERT_FROM}
email_reply_to: ${ALERT_FROM}

smtp_starttls: true
smtp_ssl: false

# 🔐 Security (IMPORTANT)
verify_certs: true
```

---

## Step 3 — Gmail SMTP Setup (replace Slack)

We configure ElastAlert2 to send email alerts via a Gmail (or Google Workspace) SMTP account. Using Gmail typically requires an App Password for accounts with 2FA enabled.

1. Create an App Password in your Google Account (or use a service account SMTP user).
2. Store credentials in environment variables and an `smtp_auth.yaml` file (already mounted by the Docker Compose example above).

Create a `.env` file (do NOT commit to GitHub):
```bash
# .env
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your-account@gmail.com
SMTP_PASS=your-app-password
ALERT_FROM=alerts@your-domain.com      # or your-account@gmail.com
ALERT_TO=oncall@example.com
```

Create `elastalert2/smtp_auth.yaml` (mounted into the container at `/opt/elastalert/smtp_auth.yaml`) with credentials in YAML format:
```yaml
# smtp_auth.yaml (keep this file private)
user: "${SMTP_USER}"
password: "${SMTP_PASS}"
```

Add `.env` to `.gitignore` if not already excluded:
```bash
echo ".env" >> .gitignore
```

---

## Step 4 — Alert Rules

### Rule 1: High HTTP Error Rate

Triggers when 5xx errors exceed 10 in a 5-minute window.

**`elastalert2/rules/high-error-rate.yml`**
```yaml
name: High HTTP Error Rate
type: frequency

index: nginx-access-*

num_events: 10
timeframe:
  minutes: 5

filter:
  - range:
      http_status_code:
        gte: 500

alert:
  - email

email:
  - ${ALERT_TO}
```

---

### Rule 2: SSH Brute Force Detection

Triggers when the same IP has 5+ failed SSH logins in 10 minutes.

**`elastalert2/rules/ssh-brute-force.yml`**
```yaml
name: SSH Brute Force Detection
type: frequency

index: auth-logs-*

# Trigger if 5 failed attempts
num_events: 5

timeframe:
  minutes: 10

# Group by attacker IP
query_key: ssh_source_ip

filter:
  - query:
      query_string:
        query: "Failed password"

  minutes: 30

alert:
  - email

email:
  - ${ALERT_TO}


alert_subject: "🔒 SSH Brute Force from {0}"

alert_subject_args:
  - ssh_source_ip

alert_text: |
  SSH brute force detected.

  IP: {0}
  Attempts: {1}

alert_text_args:
  - ssh_source_ip
  - num_hits
```

---

### Rule 3: Application Error Spike

Triggers when error count increases >300% compared to the previous hour baseline.

**`elastalert2/rules/app-error-spike.yml`**
```yaml
name: Application Error Spike
type: spike

index: app-logs-*

spike_height: 3
spike_type: up

timeframe:
  hours: 1

filter:
  - terms:
      log_level:
        - ERROR
        - FATAL

query_key: service_name

threshold_cur: 5
threshold_ref: 2

  hours: 2

alert:
  - email

email:
  - ${ALERT_TO}

alert_text: |
  ⚠️ Application Error Spike Detected

  Service: {0}
  Current Count: {1}
  Baseline: {2}
  Spike: {3}x

alert_text_args:
  - service_name
  - spike_count
  - reference_count
  - spike_height
```

---

### Rule 4: Slow Response Time Alert

Triggers when P95 response time exceeds 2000ms.

**`elastalert2/rules/slow-response-time.yml`**
```yaml
name: High Response Time P95
type: metric_aggregation

index: app-logs-*

buffer_time:
  minutes: 5

metric_agg_key: response_time_ms
metric_agg_type: percentile
percentile_range: 95

max_threshold: 2000

# Avoid noise
min_doc_count: 10

  minutes: 10

alert:
  - email

email:
  - ${ALERT_TO}


alert_text: |
  🐢 Slow Response Time Detected

  P95: {0} ms
  Threshold: 2000 ms

alert_text_args:
  - metric_agg_value
```

---

### Rule 5: Elasticsearch Disk Usage Warning

Triggers when Elasticsearch indices exceed 15GB total.

**`elastalert2/rules/disk-usage-warning.yml`**
```yaml
name: High Index Storage Usage
type: any

index: _all

timeframe:
  minutes: 10

filter:
  - range:
      _size:
        gte: 1000000000   # adjust based on your data

  hours: 4

alert:
  - email

email:
  - ${ALERT_TO}


alert_text: |
  💾 Elasticsearch Storage Warning

  Storage usage is increasing.
  Consider cleanup or ILM policies.
```

---

## Step 5 — Test Your Alerts

```bash
# 1. Generate 15 fake 500 errors to trigger the error rate alert
for i in {1..15}; do
  echo "10.0.0.$i - - [$(date +'%d/%b/%Y:%H:%M:%S +0000')] \"GET /api/fail HTTP/1.1\" 500 128 \"-\" \"test\"" \
    >> /var/log/nginx/access.log
done

# 2. Generate fake SSH failures to trigger brute-force alert
for i in {1..6}; do
  echo "$(date +'%b %d %H:%M:%S') elk-server sshd[12345]: Failed password for root from 192.168.99.99 port $((40000 + i)) ssh2" \
    >> /var/log/auth.log
done

# 3. Check ElastAlert2 logs
docker logs elastalert2 -f

# 4. Verify elastalert_status index in ES
curl -X GET "http://localhost:9200/elastalert_status/_search?pretty&size=5"

# 5. List all rule statuses
curl -X GET "http://localhost:9200/elastalert_status/_search?pretty" -H 'Content-Type: application/json' -d'
{
  "query": { "match_all": {} },
  "sort": [{ "@timestamp": "desc" }],
  "size": 10
}'
```

---

## Step 6 — Kibana Watcher (Reference — Requires License)

Watcher is Kibana's built-in alerting. Shown here as reference for enterprise environments.

**`watcher/error-spike-watcher.json`**
```json
{
  "trigger": {
    "schedule": {
      "interval": "5m"
    }
  },
  "input": {
    "search": {
      "request": {
        "indices": ["nginx-access-*"],
        "body": {
          "query": {
            "bool": {
              "filter": [
                { "range": { "@timestamp": { "gte": "now-5m" } } },
                { "range": { "http_status_code": { "gte": 500 } } }
              ]
            }
          },
          "aggs": {
            "error_count": { "value_count": { "field": "http_status_code" } }
          }
        }
      }
    }
  },
  "condition": {
    "compare": {
      "ctx.payload.aggregations.error_count.value": {
        "gt": 10
      }
    }
  },
  "actions": {
    "notify_email": {
      "email": {
        "to": ["${ALERT_TO}"],
        "subject": "🚨 High error rate detected",
        "priority": "high",
        "body": {
          "text": "High error rate: {{ctx.payload.aggregations.error_count.value}} errors in last 5 minutes"
        }
      }
    }
  }
}
```

Create via API:
```bash
curl -X PUT "http://localhost:9200/_watcher/watch/error-spike-watch" \
  -H 'Content-Type: application/json' \
  -d @watcher/error-spike-watcher.json
```

---

## ✅ Phase 4 Checklist

- [ ] ElastAlert2 container running (`docker compose ps` shows `elastalert2 Up`)
- [ ] SMTP / Gmail credentials configured (not committed to GitHub)
- [ ] All 5 alert rules created in `rules/` directory
- [ ] High error rate alert tested and email received
- [ ] SSH brute-force alert tested and email received
- [ ] `elastalert_status` index exists in Elasticsearch
- [ ] `.env` added to `.gitignore`

---

## 🧠 Concepts You Learned in Phase 4

- **ElastAlert2 rule types:** `frequency` (count of events), `spike` (relative increase), `metric_aggregation` (aggregate value threshold), `any` (any matching document).
- **`realert` cooldown** prevents alert storms — after firing, the same alert won't fire again for the specified duration.
- **`query_key`** groups alerts by a field value — with brute-force detection, you want one alert per attacking IP, not one combined alert.
- **MTTD (Mean Time to Detect)** — with 1-minute ElastAlert2 intervals, your MTTD is ≤1 minute. This is a strong talking point in interviews about your alerting design.
- **Spike detection** uses a sliding baseline window — smarter than fixed thresholds because it adapts to normal daily traffic patterns.

---

## ➡️ Next Step

Proceed to **[Phase 5 — Security, IaC & Hardening](../phase-5-hardening/README.md)**
