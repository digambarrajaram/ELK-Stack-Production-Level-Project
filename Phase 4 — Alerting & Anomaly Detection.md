# Phase 4 — Alerting & Anomaly Detection

> **Goal:** Set up ElastAlert2 with real alert rules — spike detection, brute-force detection, error-rate threshold alerts — all wired to Slack notifications. Then add Elasticsearch Watcher for metric-based alerting.  
> **Time estimate:** 3–4 hours  
> **What you'll learn:** ElastAlert2 rule types, Watcher queries, Slack webhook integration, alert tuning, MTTD concepts

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
    volumes:
      - ./phase-4-alerting/elastalert2/config.yml:/opt/elastalert/config.yml:ro
      - ./phase-4-alerting/elastalert2/rules:/opt/elastalert/rules:ro
    networks:
      - elk-net
    depends_on:
      elasticsearch:
        condition: service_healthy
    restart: unless-stopped
```

---

## Step 2 — ElastAlert2 Base Config

**`elastalert2/config.yml`**
```yaml
# Elasticsearch connection
es_host: elasticsearch
es_port: 9200

# How often ElastAlert2 queries ES (in minutes)
run_every:
  minutes: 1

# How far back to look on startup (in case EA was down)
buffer_time:
  minutes: 15

# Index to store ElastAlert2 metadata
writeback_index: elastalert_status

# Alert on connection errors
alert_on_error: true

# Timezone
use_local_time: false

# Rules directory
rules_folder: /opt/elastalert/rules

# Logging
logging_level: INFO
```

---

## Step 3 — Slack Webhook Setup

1. Go to your Slack workspace → **Apps → Incoming Webhooks → Add New Webhook**
2. Choose a channel (e.g., `#alerts`)
3. Copy the Webhook URL: `https://hooks.slack.com/services/T.../B.../xxx`

Create a `.env` file (do NOT commit to GitHub):
```bash
# .env
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK
```

Add `.env` to `.gitignore`:
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

# Index to query
index: nginx-access-*

# Trigger when this many events match in the time window
num_events: 10
timeframe:
  minutes: 5

# Filter — only look at 5xx errors
filter:
  - range:
      http_status_code:
        gte: 500

# Group alerts by status code (separate alert per code)
query_key: http_status_code

# Realert cooldown (don't spam the same alert)
realert:
  minutes: 15

# Slack notification
alert:
  - slack

slack_webhook_url: "YOUR_SLACK_WEBHOOK_URL"

slack_msg_color: danger

alert_text: |
  🚨 *High HTTP Error Rate Detected*

  *Index:* nginx-access-*
  *Status Code:* {0}
  *Error Count:* {1} errors in last 5 minutes
  *Threshold:* 10 errors

  <http://YOUR_EC2_IP:5601/app/discover#/|View in Kibana>

alert_text_args:
  - http_status_code
  - num_hits

# Include these fields in the alert body
include:
  - http_status_code
  - url_path
  - client_ip
  - "@timestamp"
```

---

### Rule 2: SSH Brute Force Detection

Triggers when the same IP has 5+ failed SSH logins in 10 minutes.

**`elastalert2/rules/ssh-brute-force.yml`**
```yaml
name: SSH Brute Force Attempt
type: frequency

index: syslog-*

num_events: 5
timeframe:
  minutes: 10

filter:
  - term:
      security_event: "ssh_failed_login"

# Group by source IP — alert when ONE IP triggers threshold
query_key: ssh_source_ip

realert:
  hours: 1

alert:
  - slack

slack_webhook_url: "YOUR_SLACK_WEBHOOK_URL"

slack_msg_color: danger

alert_subject: "🔒 SSH Brute Force from {0}"
alert_subject_args:
  - ssh_source_ip

alert_text: |
  🔒 *SSH Brute Force Attack Detected*

  *Source IP:* {0}
  *Failed Attempts:* {1} in last 10 minutes
  *Target User(s):* Multiple
  *Recommended Action:* Block IP in Security Group

  Run to block: `aws ec2 authorize-security-group-ingress --revoke ...`

alert_text_args:
  - ssh_source_ip
  - num_hits

include:
  - ssh_source_ip
  - ssh_failed_user
  - "@timestamp"
  - syslog_host
```

---

### Rule 3: Application Error Spike

Triggers when error count increases >300% compared to the previous hour baseline.

**`elastalert2/rules/app-error-spike.yml`**
```yaml
name: Application Error Spike
type: spike

index: app-logs-*

# Trigger when current window is 3x the baseline
spike_height: 3
spike_type: up

# Current window vs baseline window
timeframe:
  hours: 1

# Only count ERROR/FATAL events
filter:
  - terms:
      log_level:
        - ERROR
        - FATAL

# Group by service
query_key: service_name

# Minimum events before spiking (avoids alert on 0→1)
threshold_cur: 5
threshold_ref: 2

realert:
  hours: 2

alert:
  - slack

slack_webhook_url: "YOUR_SLACK_WEBHOOK_URL"

slack_msg_color: warning

alert_text: |
  ⚠️ *Application Error Spike Detected*

  *Service:* {0}
  *Current Error Count:* {1}
  *Baseline (previous hour):* {2}
  *Spike Factor:* {3}x

  <http://YOUR_EC2_IP:5601/app/discover#/?_g=(time:(from:now-1h,to:now))&_a=(query:(language:kql,query:'log_level:ERROR'))|View Errors in Kibana>

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

# Run every minute
buffer_time:
  minutes: 5

# Use 95th percentile of response_time_ms
metric_agg_key: response_time_ms
metric_agg_type: percentile
percentile_range: 95

# Trigger when P95 > 2000ms
max_threshold: 2000

realert:
  minutes: 10

alert:
  - slack

slack_webhook_url: "YOUR_SLACK_WEBHOOK_URL"

slack_msg_color: warning

alert_text: |
  🐢 *Slow Response Time Detected*

  *P95 Response Time:* {0}ms
  *Threshold:* 2000ms
  *Time Window:* Last 5 minutes

  Services experiencing slowness may need investigation.

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

# Query ES cluster stats endpoint via HTTP
# We check this via a custom ES query on a system index

index: .monitoring-es-*

timeframe:
  minutes: 10

filter:
  - range:
      indices.store.size_in_bytes:
        gte: 16106127360  # 15 GB in bytes

realert:
  hours: 4

alert:
  - slack

slack_webhook_url: "YOUR_SLACK_WEBHOOK_URL"

slack_msg_color: warning

alert_text: |
  💾 *Elasticsearch Storage Warning*

  Index storage is approaching limits.
  Consider running ILM rollover or deleting old indices.

  <http://YOUR_EC2_IP:5601/app/management/data/index_lifecycle_management|View ILM Policies>
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
    "notify_slack": {
      "webhook": {
        "scheme": "https",
        "host": "hooks.slack.com",
        "port": 443,
        "method": "post",
        "path": "/services/YOUR/SLACK/WEBHOOK",
        "params": {},
        "headers": { "Content-Type": "application/json" },
        "body": "{\"text\": \"🚨 High error rate: {{ctx.payload.aggregations.error_count.value}} errors in last 5 minutes\"}"
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
- [ ] Slack webhook URL configured (not committed to GitHub)
- [ ] All 5 alert rules created in `rules/` directory
- [ ] High error rate alert tested and Slack message received
- [ ] SSH brute-force alert tested and Slack message received
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
