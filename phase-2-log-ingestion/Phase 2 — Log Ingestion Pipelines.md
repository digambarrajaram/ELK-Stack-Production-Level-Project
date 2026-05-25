# Phase 2 — Log Ingestion Pipelines

> **Goal:** Configure Filebeat to collect logs and write Logstash pipelines with Grok filters to parse Nginx, application JSON, and syslog data into structured Elasticsearch documents.  
> **Time estimate:** 3–4 hours  
> **What you'll learn:** Filebeat inputs/outputs, Logstash pipeline anatomy, Grok pattern writing, field enrichment, multi-pipeline architecture

---

## 📐 Data Flow

```
/var/log/nginx/access.log  ──►
/var/log/myapp/app.log     ──► Filebeat ──► Logstash ──► Elasticsearch
/var/log/syslog            ──►               (Grok)       (indexed)
                                              (Filter)
                                              (Enrich)
```

---

## Step 1 — Filebeat Configuration

Filebeat watches log files and ships lines to Logstash.

**`filebeat/filebeat.yml`**
```yaml
# =============================================================================
# Filebeat — single Logstash output on port 5044
# The [log_type] field drives routing inside combined.conf
# =============================================================================

filebeat.inputs:

  # ---------------------------------------------------------------------------
  # Application JSON logs  ->  log_type: app_json
  # ---------------------------------------------------------------------------
  - type: log
    id: app-json-logs
    enabled: true
    paths:
      - /var/log/myapp/*.log
      - /var/log/myapp/**/*.log
    fields:
      log_type: "app_json"
    fields_under_root: true
    include_lines: ['^\{']

  # ---------------------------------------------------------------------------
  # Nginx access logs  ->  log_type: nginx_access
  # ---------------------------------------------------------------------------
  - type: log
    id: nginx-access-logs
    enabled: true
    paths:
      - /var/log/nginx/access.log
      - /var/log/nginx/access.log.*
    fields:
      log_type: "nginx_access"
    fields_under_root: true
    exclude_files: ['\.gz$']

  # ---------------------------------------------------------------------------
  # Syslog  ->  log_type: syslog
  # ---------------------------------------------------------------------------
  - type: log
    id: syslog-logs
    enabled: true
    paths:
      - /var/log/syslog
      - /var/log/syslog.*
      - /var/log/auth.log
      - /var/log/kern.log
    fields:
      log_type: "syslog"
    fields_under_root: true
    exclude_files: ['\.gz$']

# =============================================================================
# Processors
# =============================================================================
processors:
  - add_host_metadata:
      when.not.contains.tags: forwarded
  - add_docker_metadata: ~

# =============================================================================
# Output — everything goes to one port, combined.conf routes internally
# =============================================================================
output.logstash:
  hosts: ["logstash:5044"]

# =============================================================================
# Logging
# =============================================================================
logging.level: info

setup.kibana:
  host: "kibana:5601"

setup.template.enabled: false
setup.ilm.enabled: false
```

---

## Step 2 — Logstash Pipelines

We use **multiple pipelines** — one per log type. This is a production pattern that keeps configs clean and allows independent scaling.

### 2.1 Enable multi-pipeline in Logstash

Create `configs/pipelines.yml` (mount this into the Logstash container):

```yaml
# /usr/share/logstash/config/pipelines.yml
# =============================================================================
# Logstash Pipelines — single pipeline, single port 5044
# Delete or move out any old nginx.conf / app-logs.conf / syslog.conf
# so Logstash does not load them alongside this one.
# =============================================================================

- pipeline.id: main
  path.config: "/usr/share/logstash/pipeline/combined.conf"
  pipeline.workers: 2
  pipeline.batch.size: 125
  pipeline.batch.delay: 50

```

---

### 2.2 Combined Pipeline for Nginx Access Log, Application JSON Log and Syslog Pipeline

**`logstash/pipelines/combined.conf`**
```ruby
# =============================================================================
# combined.conf  —  Single Beats input on port 5044
# Routing is driven by the [log_type] field set in filebeat.yml:
#   log_type: nginx_access  ->  nginx-access-YYYY.MM.dd
#   log_type: app_json      ->  app-logs-YYYY.MM.dd
#   log_type: syslog        ->  syslog-YYYY.MM.dd
# =============================================================================

input {
  beats {
    port => 5044
  }
}

# =============================================================================
# FILTERS
# =============================================================================

filter {

  # ---------------------------------------------------------------------------
  # NGINX ACCESS LOGS
  # ---------------------------------------------------------------------------
  if [log_type] == "nginx_access" {

  grok {
    match => {
      "message" => '%{IPORHOST:client_ip} - (%{DATA:user}|-) \[%{HTTPDATE:request_time}\] "%{WORD:http_method} %{DATA:request_path} HTTP/%{NUMBER:http_version}" %{NUMBER:http_status_code:int} %{NUMBER:response_bytes:int} "%{DATA:referrer}" "%{DATA:user_agent}"'
    }
    tag_on_failure => ["_grok_parse_failure"]
  }

  date {
    match => ["request_time", "dd/MMM/yyyy:HH:mm:ss Z"]
    target => "@timestamp"
  }

  if [http_status_code] {
    if [http_status_code] >= 500 {
      mutate { add_field => { "status_category" => "5xx_server_error" } }
    } else if [http_status_code] >= 400 {
      mutate { add_field => { "status_category" => "4xx_client_error" } }
    } else if [http_status_code] >= 300 {
      mutate { add_field => { "status_category" => "3xx_redirect" } }
    } else if [http_status_code] >= 200 {
      mutate { add_field => { "status_category" => "2xx_success" } }
    }
  }

  # Fixed GeoIP processing block (Removed restrictive sub-field filtering arrays)
  if [client_ip] and "_grok_parse_failure" not in [tags] {
    geoip {
      source => "client_ip"
      target => "geoip"
    }
  }

  useragent {
    source => "user_agent"
    target => "ua"
  }

  if [request_path] {
    grok {
      match => { "request_path" => "^%{URIPATH:url_path}(?:\?%{GREEDYDATA:url_query})?" }
    }
  }

  # Safe cleanup: Keep tracking components alive
  if "_grok_parse_failure" not in [tags] {
    mutate {
      remove_field => ["message", "request_time"]
    }
  }

  mutate {
    add_field => { "[@metadata][target_index]" => "nginx-access-%{+YYYY.MM.dd}" }
  }
}


  # ---------------------------------------------------------------------------
  # APPLICATION JSON LOGS
  # ---------------------------------------------------------------------------
  else if [log_type] == "app_json" {

    json {
      source => "message"
      target => "app"
      tag_on_failure => ["_json_parse_failure"]
    }

    if "_json_parse_failure" not in [tags] {
      mutate {
        rename => {
          "[app][level]"          => "log_level"
          "[app][message]"        => "log_message"
          "[app][service]"        => "service_name"
          "[app][trace_id]"       => "trace_id"
          "[app][response_time]"  => "response_time_ms"
          "[app][status_code]"    => "http_status_code"
          "[app][error]"          => "error_message"
        }
      }
    }

    if [app][timestamp] {
      date {
        match => ["[app][timestamp]", "ISO8601", "yyyy-MM-dd HH:mm:ss"]
        target => "@timestamp"
        remove_field => ["[app][timestamp]"]
      }
    }

    if [log_level] {
      mutate { uppercase => ["log_level"] }
    }

    if [response_time_ms] and [response_time_ms] > 1000 {
      mutate {
        add_tag   => ["slow_request"]
        add_field => { "performance_flag" => "slow" }
      }
    }

    if [log_level] == "ERROR" or [log_level] == "FATAL" {
      mutate { add_tag => ["error"] }
    }

    mutate {
      remove_field => ["message", "agent", "ecs", "host", "input"]
      add_field    => { "[@metadata][target_index]" => "app-logs-%{+YYYY.MM.dd}" }
    }

  }

  # ---------------------------------------------------------------------------
  # SYSLOG
  # ---------------------------------------------------------------------------
  else if [log_type] == "syslog" {

    # If Filebeat placed the raw/syslog line in event.original (common for modern beats),
    # use that as the source for parsing so we don't rely only on the incoming [message] field.
    if [event][original] {
      mutate {
        replace => { "message" => "%{[event][original]}" }
      }
    }

    # Patterns to handle ISO8601-prefixed lines, standard syslog, Docker-prefixed, and a fallback.
    grok {
      match => {
        "message" => [
          # ISO8601 timestamp then host and program: "2026-05-23T17:00:58.571431+00:00 hostname program[pid]: message"
          "%{TIMESTAMP_ISO8601:syslog_timestamp} %{SYSLOGHOST:syslog_host} %{DATA:syslog_program}(?:\[%{POSINT:syslog_pid}\])?: %{GREEDYDATA:syslog_message}",
          # Standard: "May 24 11:04:19 hostname program[pid]: message"
          "%{SYSLOGTIMESTAMP:syslog_timestamp} %{SYSLOGHOST:syslog_host} %{DATA:syslog_program}(?:\[%{POSINT:syslog_pid}\])?: %{GREEDYDATA:syslog_message}",
          # Docker-prefixed: "hostname May 24 11:04:19 hostname program[pid]: message"
          "%{SYSLOGHOST} %{SYSLOGTIMESTAMP:syslog_timestamp} %{SYSLOGHOST:syslog_host} %{DATA:syslog_program}(?:\[%{POSINT:syslog_pid}\])?: %{GREEDYDATA:syslog_message}",
          # Fallback: grab whatever is after timestamp for debugging
          "%{SYSLOGTIMESTAMP:syslog_timestamp} %{GREEDYDATA:syslog_message}"
        ]
      }
      tag_on_failure => ["_syslog_parse_failure"]
    }

    # Ubuntu/systemd syslog lines carry microsecond-precision timestamps, e.g.:
    #   "2026-05-23T17:00:58.570533+00:00"
    # Logstash's "ISO8601" shorthand uses Joda-time, which only parses up to
    # milliseconds (3 decimal places). Six decimal places causes a silent parse
    # failure, leaving @timestamp at ingest time instead of the log's real time.
    #
    # Fix: list the explicit Joda pattern with 6-digit fractional seconds first,
    # then fall back to "ISO8601" (covers 0–3 decimal places), then the legacy
    # syslog month/day formats for older log lines.
    date {
      match => [
        "syslog_timestamp",
        "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZ",
        "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
        "ISO8601",
        "MMM  d HH:mm:ss",
        "MMM dd HH:mm:ss",
        "MMM d HH:mm:ss"
      ]
      target => "@timestamp"
      remove_field => ["syslog_timestamp"]
    }

    if [syslog_program] == "sshd" {
      if [syslog_message] =~ /Failed password/ {
        grok {
          match => {
            "syslog_message" => "Failed password for (?:invalid user )?%{USERNAME:ssh_failed_user} from %{IPORHOST:ssh_source_ip}"
          }
          tag_on_failure => ["_ssh_grok_failure"]
        }
        mutate {
          add_tag   => ["ssh_failed_login"]
          add_field => { "security_event" => "ssh_failed_login" }
        }
      }

      if [syslog_message] =~ /Accepted/ {
        mutate {
          add_tag   => ["ssh_success"]
          add_field => { "security_event" => "ssh_success" }
        }
      }
    }

    if [syslog_message] =~ /Out of memory/ or [syslog_message] =~ /oom-kill/ {
      mutate {
        add_tag   => ["oom_event"]
        add_field => { "system_event" => "oom_kill" }
      }
    }

    if [syslog_message] =~ /No space left on device/ {
      mutate {
        add_tag   => ["disk_full"]
        add_field => { "system_event" => "disk_full" }
      }
    }

    mutate {
      remove_field => ["message", "agent", "ecs", "host", "input"]
      add_field    => { "[@metadata][target_index]" => "syslog-%{+YYYY.MM.dd}" }
    }

  }

  # ---------------------------------------------------------------------------
  # UNKNOWN log_type — drop so nothing unintended reaches Elasticsearch
  # ---------------------------------------------------------------------------
  else {
    drop { }
  }

}

# =============================================================================
# OUTPUT — single block, index driven by [@metadata][target_index]
# [@metadata] is ephemeral and never stored in Elasticsearch
# =============================================================================

output {
  elasticsearch {
    hosts => ["elasticsearch:9200"]
    index => "%{[@metadata][target_index]}"
  }
  # Uncomment to debug in Logstash container logs:
  # stdout { codec => rubydebug }
}
```

---

## Step 3 — Generate Sample Logs (for testing)

Since you may not have real Nginx installed yet, generate fake logs to test your pipeline:

```bash
# Generate sample Nginx access logs
cat <<'EOF' > /var/log/nginx/access.log
192.168.1.100 - john [25/Jan/2024:10:15:32 +0000] "GET /api/users HTTP/1.1" 200 1024 "-" "Mozilla/5.0"
10.0.0.5 - - [25/Jan/2024:10:15:33 +0000] "POST /api/login HTTP/1.1" 401 256 "-" "curl/7.68.0"
203.0.113.42 - - [25/Jan/2024:10:15:34 +0000] "GET /admin HTTP/1.1" 403 512 "-" "python-requests/2.28.0"
8.8.8.8 - - [25/Jan/2024:10:15:35 +0000] "GET /index.html HTTP/1.1" 200 4096 "https://google.com" "Chrome/120"
198.51.100.1 - - [25/Jan/2024:10:15:36 +0000] "DELETE /api/item/42 HTTP/1.1" 500 128 "-" "insomnia/2023"
EOF

# Generate sample app JSON logs
cat <<'EOF' > /var/log/myapp/app.log
{"timestamp":"2024-01-25T10:15:30Z","level":"INFO","service":"api-gateway","message":"Request received","trace_id":"abc-123","response_time":45,"status_code":200}
{"timestamp":"2024-01-25T10:15:31Z","level":"ERROR","service":"auth-service","message":"JWT validation failed","trace_id":"def-456","error":"token expired","status_code":401}
{"timestamp":"2024-01-25T10:15:32Z","level":"WARN","service":"db-service","message":"Slow query detected","trace_id":"ghi-789","response_time":2350,"status_code":200}
{"timestamp":"2024-01-25T10:15:33Z","level":"INFO","service":"payment-service","message":"Payment processed","trace_id":"jkl-012","response_time":120,"status_code":200}
EOF

echo "$(date '+%b %d %H:%M:%S') ip-172-31-44-10 sshd[12345]: Failed password for invalid user hacker from 192.168.1.100 port 54321 ssh2" | sudo tee -a /var/log/auth.log

echo '1.2.3.4 - - [25/May/2026:09:56:00 +0000] "GET /api/v1/data HTTP/1.1" 200 4523 "-" "Mozilla/5.0"' | sudo tee -a /var/log/nginx/access.log

```

 

---

## Step 4 — Verify Ingestion

```bash
# Check indices were created
curl -X GET "http://localhost:9200/_cat/indices?v"
# Should see: nginx-access-YYYY.MM.DD, app-logs-YYYY.MM.DD, syslog-YYYY.MM.DD

# Count documents in nginx index
curl -X GET "http://localhost:9200/nginx-access-*/_count?pretty"

# Search for all 5xx errors
curl -X GET "http://localhost:9200/nginx-access-*/_search?pretty" -H 'Content-Type: application/json' -d'
{
  "query": {
    "range": {
      "http_status_code": { "gte": 500 }
    }
  }
}'

# Search for failed SSH logins
curl -X GET "http://localhost:9200/syslog-*/_search?pretty" -H 'Content-Type: application/json' -d'
{
  "query": {
    "term": { "security_event": "ssh_failed_login" }
  }
}'

# Check Logstash pipeline stats
curl -X GET "http://localhost:9600/_node/stats/pipelines?pretty"
```

---

## Step 5 — Explore in Kibana

1. Access KibanaOpen your web browser.Enter your EC2 instance URL: http://<EC2_IP>:5601
(replace <EC2_IP> with your actual AWS EC2 public IP address).Log in using your Kibana credentials if prompted.
2. Navigate to Index PatternsClick the Burger Menu icon (three horizontal lines) in the top-left corner.Scroll down to the bottom section.Click on Management (or Stack Management).In the left sidebar, under the Kibana section, click on Data Views.
3. Create the Index Patterns You need to repeat these sub-steps for each of your three log sources:
For Nginx Access Logs:Click the Create data view button.In the Name field, type exactly: nginx-access, Index Pattern: nginx-access-*, Select @timestamp from the Timestamp field dropdown menu.Click Create index pattern. 
For Application Logs:Click Create data view again.In the Name field, type exactly: app-logs, Index Pattern: app-logs-*, Select @timestamp from the Timestamp field dropdown menu.Click Create index pattern.
For System Logs:Click Create data view a final time.In the Name field, type exactly: syslog, Index Pattern: syslog-*, Select @timestamp from the Timestamp field dropdown menu.Click Create index pattern.
3. Access the Discover Tab. Click the Burger Menu icon in the top-left corner again.Click on Discover (usually located near the top under the Analytics section).Look at the top-left section of the Discover page, just below the search bar.Click the dropdown menu showing the current index pattern and switch to the one you want to investigate (e.g., nginx-access-*).
4. Test KQL QueriesType these example Kibana Query Language (KQL) queries into the top search bar to filter your data.

```kql
# All server errors
http_status_code >= 500

# Slow application requests
response_time_ms > 1000

# Failed SSH attempts
tags: "ssh_failed_login"

# Errors from a specific service
service_name: "auth-service" AND log_level: "ERROR"

# Requests from a specific country
geoip.country_name: "China"
```

---

## ✅ Phase 2 Checklist

- [ ] Filebeat is running and shipping logs (check `docker logs filebeat`)
- [ ] Three indices appear in `_cat/indices`: nginx, app-logs, syslog
- [ ] Nginx logs are parsed — `client_ip`, `http_status_code`, `url_path` fields visible
- [ ] App logs are parsed — `log_level`, `service_name`, `response_time_ms` fields visible
- [ ] SSH failed login events are tagged in syslog index
- [ ] KQL queries return correct results in Kibana Discover

---

## 🧠 Concepts You Learned in Phase 2

- **Grok** is a pattern-matching language that turns unstructured log lines into structured fields. Pattern: `%{SYNTAX:SEMANTIC}` where SYNTAX is the pattern name and SEMANTIC is the field name.
- **Multi-pipeline Logstash** lets you run separate pipelines concurrently — better isolation and performance than one big pipeline.
- **GeoIP enrichment** adds geographic context to IP addresses for map visualizations in Kibana.
- **`fields_under_root: true`** in Filebeat promotes custom fields to the top-level document (not nested under `fields`).
- **`tag_on_failure`** in Grok/JSON filters adds a tag when parsing fails — lets you query and debug unparsed events easily.
- **`_grok_parse_failure`** in an index means your pattern doesn't match some log lines — always monitor this.

---

## ➡️ Next Step

Proceed to **[Phase 3 — Kibana Dashboards](../phase-3-kibana-dashboards/README.md)**
