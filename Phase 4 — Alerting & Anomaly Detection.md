# Phase 4 — Alerting & Anomaly Detection

> **Goal:** Set up ElastAlert2 with real alert rules — spike detection, brute-force detection, error-rate threshold alerts — all wired to email notifications (Gmail SMTP). Then add Elasticsearch Watcher for metric-based alerting.  
> **Time estimate:** 3–4 hours  
> **What you'll learn:** ElastAlert2 rule types, Watcher queries, SMTP/Gmail integration, alert tuning, MTTD concepts

---

## 📐 Alerting Architecture

```
Elasticsearch Indices
        │
        ├──► ElastAlert2 ──► Email / Slack
        │    (scheduled     (notifications)
        │     queries)
        │
        └──► Kibana Watcher ──► Email / Slack
             (built-in,          (notifications)
              paid feature)
```

> **Note:** ElastAlert2 is open-source and free. Kibana Watcher requires a paid X-Pack license. We primarily use ElastAlert2, with Watcher shown as reference for enterprise environments.

---

## Step 0 — Directory Structure

Ensure your project has this structure:

```
ELK_Stack/
├── docker-compose.yml
├── .env                          (not in git)
├── .gitignore
├── phase-4-alerting/
│   ├── test-all-alerts.sh
│   └── elastalert2/
│       ├── config.yml
│       ├── smtp_auth.yaml        
│       ├── data/                 (created by docker)
│       ├── rules/
│       │   ├── high-error-rate.yml
│       │   ├── ssh-brute-force.yml
│       │   ├── app-error-spike.yml
│       │   ├── slow-response-time.yml
│       │   └── disk-usage-warning.yml
│       └── watcher/
│           └── error-spike-watcher.json
```

---

## Step 1 — Docker Compose Configuration

Your `docker-compose.yml` already includes the ElastAlert2 service:

```yaml
elastalert:
  image: jertel/elastalert2:latest
  container_name: elastalert2

  env_file:
    - .env

  volumes:
    - ./phase-4-alerting/elastalert2/config.yml:/opt/elastalert/config.yaml:ro
    - ./phase-4-alerting/elastalert2/rules:/opt/elastalert/rules:ro
    - ./phase-4-alerting/elastalert2/data:/opt/elastalert/data
    - ./phase-4-alerting/elastalert2/smtp_auth.yaml:/opt/elastalert/smtp_auth.yaml:ro

  environment:
    - TZ=Asia/Kolkata

  depends_on:
    elasticsearch:
      condition: service_healthy

  networks:
    - elk-net

  restart: unless-stopped
```

**Key Points:**
- `config.yaml` file is mounted read-only
- Rules directory mounted for live rule discovery
- SMTP auth file mounted with credentials
- Depends on healthy Elasticsearch
- Automatic restart on failure

---

## Step 2 — Environment Variables Setup

Create a `.env` file in your project root (do NOT commit to GitHub):

```bash
# .env
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your-email@gmail.com
SMTP_PASS=your-app-password
ALERT_FROM=alerts@your-domain.com
ALERT_TO=oncall@example.com
```

**Gmail App Password Setup:**
1. Go to Google Account → Security
2. Enable 2-Step Verification
3. Create an App Password for "Mail" and "Windows Computer"
4. Copy the 16-character password into `SMTP_PASS`

**Add to `.gitignore`:**
```bash
echo ".env" >> .gitignore
```

---

## Step 3 — ElastAlert2 Configuration File

**`phase-4-alerting/elastalert2/config.yml`**

```yaml
# ========================================
# ELASTICSEARCH CONNECTION
# ========================================
es_host: elasticsearch
es_port: 9200
verify_certs: false

# ========================================
# ELASTALERT SCHEDULING & BEHAVIOR
# ========================================
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

# ========================================
# SMTP EMAIL CONFIGURATION
# ========================================
smtp_host: ${SMTP_HOST}
smtp_port: ${SMTP_PORT}
smtp_auth_file: /opt/elastalert/smtp_auth.yaml

from_addr: ${ALERT_FROM}
email_reply_to: ${ALERT_FROM}

smtp_starttls: true
smtp_ssl: false

# Set to false for self-signed certs
verify_certs: true
```

---

## Step 4 — SMTP Authentication File

**`phase-4-alerting/elastalert2/smtp_auth.yaml`**

```yaml
user: ${SMTP_USER}
password: ${SMTP_PASS}
```

---

## Step 5 — Alert Rules

### Rule 1: High HTTP Error Rate

Triggers when 5xx errors exceed 10 in a 5-minute window.

**`phase-4-alerting/elastalert2/rules/high-error-rate.yml`**

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

alert_subject: "🚨 High HTTP Error Rate Detected"

alert_text: |
  High HTTP Error Rate Alert
  
  Count: {0} errors in 5 minutes
  Threshold: 10 errors
  
  Check Kibana dashboards for affected endpoints.

alert_text_args:
  - num_hits
```

---

### Rule 2: SSH Brute Force Detection

Triggers when the same IP has 5+ failed SSH logins in 10 minutes.

**`phase-4-alerting/elastalert2/rules/ssh-brute-force.yml`**

```yaml
name: SSH Brute Force Detection
type: frequency

index: auth-logs-*

# Trigger if 5 failed attempts
num_events: 5

timeframe:
  minutes: 10

# Group by attacker IP — one alert per IP
query_key: ssh_source_ip

filter:
  - query:
      query_string:
        query: "Failed password"

realert:
  minutes: 30

alert:
  - email

email:
  - ${ALERT_TO}

alert_subject: "🔒 SSH Brute Force from {0}"

alert_subject_args:
  - ssh_source_ip

alert_text: |
  SSH Brute Force Attack Detected
  
  Attacking IP: {0}
  Failed Attempts: {1}
  Timeframe: 10 minutes
  
  Recommended Actions:
  1. Block IP in firewall
  2. Review failed login timestamps
  3. Check for successful intrusions
  4. Enable fail2ban if not active

alert_text_args:
  - ssh_source_ip
  - num_hits
```

---

### Rule 3: Application Error Spike

Triggers when error count increases >300% compared to the baseline (spike detection).

**`phase-4-alerting/elastalert2/rules/app-error-spike.yml`**

```yaml
name: Application Error Spike
type: spike

index: app-logs-*

# Trigger when current count is 3x the baseline
spike_height: 3
spike_type: up

timeframe:
  hours: 1

# Only look at ERROR and FATAL level logs
filter:
  - terms:
      log_level:
        - ERROR
        - FATAL

# Group spike per service
query_key: service_name

# Must have at least 5 errors to trigger
threshold_cur: 5
# Baseline must be at least 2
threshold_ref: 2

realert:
  hours: 2

alert:
  - email

email:
  - ${ALERT_TO}

alert_subject: "⚠️ Error Spike in {0}"

alert_subject_args:
  - service_name

alert_text: |
  Application Error Spike Detected
  
  Service: {0}
  Current Error Count: {1}
  Baseline (1hr ago): {2}
  Spike Factor: {3}x
  
  Investigate service logs immediately.
  Check for:
  - Recent deployments
  - Database connection issues
  - External dependency failures
  - Memory/CPU exhaustion

alert_text_args:
  - service_name
  - spike_count
  - reference_count
  - spike_height
```

---

### Rule 4: Slow Response Time (P95 Percentile)

Triggers when 95th percentile response time exceeds 2000ms.

**`phase-4-alerting/elastalert2/rules/slow-response-time.yml`**

```yaml
name: High Response Time P95
type: metric_aggregation

index: app-logs-*

buffer_time:
  minutes: 5

# Aggregation query configuration
metric_agg_key: response_time_ms
metric_agg_type: percentiles
percentile_range: 95

max_threshold: 2000

# Require minimum 10 documents to avoid false positives
min_doc_count: 10

realert:
  minutes: 10

alert:
  - email

email:
  - ${ALERT_TO}

alert_subject: "🐢 High Response Time - P95 exceeded"

alert_text: |
  High Response Time Alert
  
  P95 Response Time: {0} ms
  Threshold: 2000 ms
  
  Action Items:
  1. Check database query performance
  2. Monitor CPU/memory on app servers
  3. Review slow query logs
  4. Check for N+1 query patterns
  5. Consider caching optimization

alert_text_args:
  - metric_agg_value
```

---

### Rule 5: Elasticsearch Disk Storage Warning

Triggers when Elasticsearch indices exceed 1GB in size.

**`phase-4-alerting/elastalert2/rules/disk-usage-warning.yml`**

```yaml
name: High Index Storage Usage
type: any

index: _all

timeframe:
  minutes: 10

# Adjust threshold based on your requirements
filter:
  - range:
      _size:
        gte: 1000000000   # 1GB in bytes

realert:
  hours: 4

alert:
  - email

email:
  - ${ALERT_TO}

alert_subject: "💾 Elasticsearch Storage Warning"

alert_text: |
  Elasticsearch Storage Usage Alert
  
  Storage usage is increasing significantly.
  
  Recommended Actions:
  1. Review Index Lifecycle Management (ILM) policies
  2. Check for uncompressed indices
  3. Consider archiving old indices
  4. Review Logstash pipeline for data duplication
  5. Verify retention policies are working

alert_text_args: []
```

---

## Step 6 — Testing Your Alerts

### Test Script: Index Sample Documents

**`phase-4-alerting/test-all-alerts.sh`**

```bash
#!/bin/bash
# Test all ElastAlert2 alert rules by indexing sample documents into Elasticsearch.
# Run this from the repository root in a shell: bash phase-4-alerting/test-all-alerts.sh

ES_URL="http://localhost:9200"
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

function post_doc() {
  local index="$1"
  local body="$2"

  echo "Indexing into $index..."
  curl -s -X POST "$ES_URL/$index/_doc" \
    -H 'Content-Type: application/json' \
    -d "$body"
  echo
}

echo "\n=== 1) High HTTP error rate ==="
for i in $(seq 1 10); do
  post_doc "nginx-access-000001" "{\"@timestamp\": \"$NOW\", \"http_status_code\": 500, \"request\": \"/api/test\", \"client_ip\": \"1.2.3.$i\", \"user_agent\": \"curl/7.90\", \"method\": \"GET\"}"
done

echo "\n=== 2) SSH brute force ==="
for i in $(seq 1 5); do
  post_doc "auth-logs-000001" "{\"@timestamp\": \"$NOW\", \"ssh_source_ip\": \"10.0.0.5\", \"message\": \"Failed password for invalid user root\", \"event\": \"ssh\", \"host\": \"bastion.example.com\"}"
done

echo "\n=== 3) Slow response time (P95) ==="
for i in $(seq 1 10); do
  post_doc "app-logs-000001" "{\"@timestamp\": \"$NOW\", \"response_time_ms\": 2200, \"service_name\": \"checkout\", \"message\": \"Response time exceeded threshold\", \"status\": \"200\"}"
done

echo "\n=== 4) Application error spike ==="
# Add baseline events and a spike for the same service_name.
post_doc "app-logs-000001" "{\"@timestamp\": \"$NOW\", \"service_name\": \"orders\", \"log_level\": \"ERROR\", \"message\": \"Baseline error event\"}"
post_doc "app-logs-000001" "{\"@timestamp\": \"$NOW\", \"service_name\": \"orders\", \"log_level\": \"ERROR\", \"message\": \"Baseline error event\"}"
for i in $(seq 1 6); do
  post_doc "app-logs-000001" "{\"@timestamp\": \"$NOW\", \"service_name\": \"orders\", \"log_level\": \"ERROR\", \"message\": \"Spike error event $i\"}"
done

echo "\n=== 5) Disk usage warning ==="
echo "NOTE: This rule checks Elasticsearch _size and may require lowering the threshold for local testing."
# Create a large document to help match size-based detection.
LARGE_MESSAGE=$(printf '%*s' 200000 | tr ' ' 'X')
post_doc "disk-usage-test-000001" "{\"@timestamp\": \"$NOW\", \"host\": \"node01\", \"message\": \"$LARGE_MESSAGE\", \"type\": \"disk_test\"}"

echo "\nAll test documents indexed."
echo "Wait 1-2 minutes for ElastAlert2 to evaluate and then check your alert email or Docker logs."
echo "If you want, run: docker logs elastalert2 --tail 100"
```

**Run the test:**
```bash
bash phase-4-alerting/test-all-alerts.sh
```

---

## Step 7 — Manual Testing & Verification

### 1. Start the Stack
```bash
docker compose up -d
docker compose logs -f elastalert2
```

### 2. Run the Alert Test Script
```bash
bash phase-4-alerting/test-all-alerts.sh
```

### 3. Verify ElastAlert2 is Running
```bash
docker ps | grep elastalert2
# Output: elastalert2 Up X minutes
```

### 4. Check ElastAlert2 Logs
```bash
docker logs elastalert2 --tail 50
```

Look for:
- `INFO: Alert 'High HTTP Error Rate' triggered!`
- SMTP connection logs
- Rule loading logs

### 5. Query ElastAlert2 Status Index
```bash
curl -X GET "http://localhost:9200/elastalert_status/_search?pretty&size=10" \
  -H 'Content-Type: application/json'
```

Expected response shows alert firing history.

### 6. Check Alert Email
- Monitor your email inbox for test alerts
- Verify sender is `${ALERT_FROM}`
- Verify recipient is `${ALERT_TO}`
- Check email formatting and content

---

## Step 8 — Kibana Watcher (Reference — Requires License)

Watcher is Kibana's built-in alerting system. Shown here for reference in enterprise environments with X-Pack licenses.

**`phase-4-alerting/elastalert2/watcher/error-spike-watcher.json`**

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

**Deploy Watcher (if X-Pack available):**
```bash
curl -X PUT "http://localhost:9200/_watcher/watch/error-spike-watch" \
  -H 'Content-Type: application/json' \
  -d @phase-4-alerting/elastalert2/watcher/error-spike-watcher.json
```

**Verify Watcher:**
```bash
curl -X GET "http://localhost:9200/_watcher/watch/error-spike-watch?pretty"
```

---
## Troubleshooting

### Issue: "No handlers could be found for logger"

**Solution:** This is a warning, not an error. Safe to ignore. It appears when ElastAlert2 initializes logging before fully loading handlers.

```bash
docker logs elastalert2 | grep -i error
```

### Issue: SMTP connection refused

**Check:**
```bash
# 1. Verify .env file exists and has correct credentials
cat .env

# 2. Test SMTP connectivity
docker exec elastalert2 telnet smtp.gmail.com 587

# 3. Verify Gmail app password is correct (not your main password)
```

### Issue: Rules not loading

**Check:**
```bash
# 1. Verify rule file syntax
docker exec elastalert2 elastalert-create-index --rules /opt/elastalert/rules

# 2. Check rule files exist
docker exec elastalert2 ls -la /opt/elastalert/rules/

# 3. View ElastAlert2 logs
docker logs elastalert2 --tail 100
```

### Issue: No alerts being triggered

**Check:**
```bash
# 1. Verify test data was indexed
curl -X GET "http://localhost:9200/nginx-access-000001/_count"

# 2. Manually query the index
curl -X GET "http://localhost:9200/nginx-access-000001/_search?pretty&size=5"

# 3. Check ElastAlert2 buffer time isn't hiding recent data
# (default 15 minutes buffer = data must be 15+ min old to be alerted on)

# 4. View full logs
docker logs elastalert2 -f
```

### Issue: Elasticsearch connection timeout

**Solution:**
```bash
# 1. Verify Elasticsearch is healthy
docker exec elasticsearch curl -s localhost:9200/_cluster/health | jq .status

# 2. Check network connectivity
docker network ls
docker network inspect elk-net

# 3. Restart ElastAlert2
docker compose restart elastalert
```

---

## Monitoring ElastAlert2

### Check Alert Status
```bash
# List all alert firings
curl -X GET "http://localhost:9200/elastalert_status/_search?pretty" \
  -H 'Content-Type: application/json' -d '
{
  "query": { "match_all": {} },
  "sort": [{ "@timestamp": "desc" }],
  "size": 20
}'
```

### Real-time Logs
```bash
docker logs elastalert2 -f --tail 100
```

### Rule Statistics
```bash
# Count how many times each rule has fired
curl -X GET "http://localhost:9200/elastalert_status/_search?pretty" \
  -H 'Content-Type: application/json' -d '
{
  "aggs": {
    "by_rule": {
      "terms": {
        "field": "rule_name.keyword",
        "size": 20
      }
    }
  }
}'
```

---

## Configuration Best Practices

### 1. Adjust Buffer Time Carefully
```yaml
# buffer_time: How long to wait before considering data "old enough" to alert on
# Too short = might miss data
# Too long = delayed alerts

buffer_time:
  minutes: 15  # Recommended for production
```

### 2. Set Appropriate Realert Intervals
```yaml
# realert: Cooldown period after an alert fires
# Prevents alert storms for recurring issues

realert:
  minutes: 30   # High-priority alerts
  # or
  hours: 2      # Low-priority alerts
```

### 3. Use query_key for Grouping
```yaml
# Groups alerts by field value instead of one combined alert
# Brute force by IP: one alert per attacking IP
# Errors by service: one alert per service

query_key: ssh_source_ip
```

### 4. Set min_doc_count to Avoid Noise
```yaml
# Requires minimum X documents before alerting
# Prevents false positives from sparse data

min_doc_count: 10
```

---

## Next Steps

### Production Hardening:
1. **TLS/SSL for Elasticsearch:** Enable X-Pack security
2. **Authentication:** Add username/password to ElastAlert2
3. **Log Rotation:** Configure Docker log rotation
4. **Metrics Monitoring:** Add Prometheus/Grafana
5. **PagerDuty Integration:** Route critical alerts to on-call

### Advanced Features:
1. **Custom Alert Formatters:** HTML email templates
2. **Webhook Alerts:** POST to Slack, PagerDuty, custom systems
3. **Alert Aggregation:** Group related alerts
4. **Multi-index Rules:** Alert on correlations across indices
5. **ML Anomaly Detection:** Use Elasticsearch ML module

---

## ✅ Phase 4 Completion Checklist

- [ ] ElastAlert2 container running (`docker compose ps` shows `elastalert2 Up`)
- [ ] `.env` file created with SMTP credentials
- [ ] `.env` added to `.gitignore`
- [ ] `config.yml` configured with correct Elasticsearch host
- [ ] `smtp_auth.yaml` created with credentials
- [ ] All 5 alert rules created in `rules/` directory
- [ ] Test alert script executed successfully
- [ ] At least one test alert received in email
- [ ] `elastalert_status` index exists in Elasticsearch
- [ ] Docker logs show no critical errors
- [ ] ElastAlert2 rules folder contains 5 YAML files
- [ ] Watcher JSON file created (reference only)

---

## 🧠 Key Concepts Learned in Phase 4

### ElastAlert2 Rule Types

| Type | Purpose | Use Case |
|------|---------|----------|
| `frequency` | Count events in timeframe | 5xx errors in 5 min |
| `spike` | Relative % increase from baseline | Error spike detection |
| `metric_aggregation` | Aggregate value threshold | P95 response time |
| `any` | Match any document | Storage threshold |
| `blacklist` / `whitelist` | Inclusion/exclusion lists | IP-based alerting |

### Alert Tuning

- **`realert` cooldown:** Prevents alert storms. After firing, same alert won't fire for X minutes/hours.
- **`query_key`:** Groups alerts by field. `query_key: ssh_source_ip` = one alert per IP, not combined.
- **`buffer_time`:** Delay before alerting. Allows time for log aggregation.
- **`min_doc_count`:** Minimum documents required. Avoids false positives from sparse data.

### MTTD (Mean Time to Detect)

With 1-minute ElastAlert2 check intervals:
- **MTTD ≤ 2 minutes** (1 min interval + 1 min buffer)
- Industry benchmark: MTTD should be < 5 minutes for most systems
- This is a strong talking point for incident response capabilities

### Spike Detection Algorithm

ElastAlert2 spike type uses a **sliding baseline window**:
1. Reference window: Previous hour's error count (baseline)
2. Current window: Last hour's error count
3. If current > (baseline × spike_height), alert fires
4. **Adaptive:** Responds to normal traffic patterns, not fixed thresholds

Example:
```
Baseline (1hr ago): 10 errors
spike_height: 3
threshold_cur: 5

Current errors: 32
Check: 32 > (10 × 3) = 30? YES → Alert fires ✅
```

### SMTP & Gmail Integration

- Gmail requires **App Password** (not main password) if 2FA enabled
- **TLS on port 587** ensures encrypted credentials transmission
- Credentials stored in YAML file (never in rules or config)
- Mounted read-only into container for security

---

## Interview Talking Points

1. **Multi-layer Alerting:** Both ElastAlert2 (free, open-source) and Watcher (enterprise) available
2. **Spike Detection:** Adaptive thresholds using baseline comparison rather than static limits
3. **Alert Grouping:** `query_key` prevents alert fatigue by consolidating related alerts
4. **MTTD < 2 minutes:** 1-minute polling interval with minimal buffer time
5. **Security:** Environment variables + SMTP auth file keeps credentials out of code
6. **Scalability:** ElastAlert2 can scale to thousands of rules with proper tuning
7. **Incident Response:** Clear, actionable alert text with troubleshooting steps

---

## ➡️ Next Phase

Proceed to **[Phase 5 — Security, IaC & Production Hardening](../Phase%205%20—%20Security,%20IaC%20&%20Production%20Hardening.md)**
