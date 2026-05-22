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
filebeat.inputs:

  # Nginx access logs
  - type: log
    id: nginx-access
    enabled: true
    paths:
      - /var/log/nginx/access.log
    tags: ["nginx", "access"]
    fields:
      log_type: nginx_access
      environment: production
    fields_under_root: true

  # Nginx error logs
  - type: log
    id: nginx-error
    enabled: true
    paths:
      - /var/log/nginx/error.log
    tags: ["nginx", "error"]
    fields:
      log_type: nginx_error
      environment: production
    fields_under_root: true

  # Application JSON logs
  - type: log
    id: app-json
    enabled: true
    paths:
      - /var/log/myapp/*.log
    tags: ["application"]
    fields:
      log_type: app_json
      environment: production
    fields_under_root: true
    # Parse multiline stack traces as single events
    multiline.pattern: '^\{'
    multiline.negate: true
    multiline.match: after

  # Syslog (auth, system events)
  - type: log
    id: syslog
    enabled: true
    paths:
      - /var/log/syslog
      - /var/log/auth.log
    tags: ["syslog"]
    fields:
      log_type: syslog
      environment: production
    fields_under_root: true

  # Docker container logs
  - type: container
    id: docker-containers
    enabled: true
    paths:
      - /var/lib/docker/containers/*/*.log
    tags: ["docker"]
    fields:
      log_type: docker
    fields_under_root: true

# Ship to Logstash (not directly to ES — we want to filter first)
output.logstash:
  hosts: ["logstash:5044"]
  loadbalance: true
  ttl: 30s

# Filebeat internal registry (tracks position in each log file)
filebeat.registry.path: /usr/share/filebeat/data/registry

# Logging
logging.level: info
logging.to_files: true
logging.files:
  path: /var/log/filebeat
  name: filebeat.log
  keepfiles: 3
```

---

## Step 2 — Logstash Pipelines

We use **multiple pipelines** — one per log type. This is a production pattern that keeps configs clean and allows independent scaling.

### 2.1 Enable multi-pipeline in Logstash

Create `configs/pipelines.yml` (mount this into the Logstash container):

```yaml
# /usr/share/logstash/config/pipelines.yml
- pipeline.id: nginx
  path.config: "/usr/share/logstash/pipeline/nginx.conf"
  pipeline.workers: 2

- pipeline.id: app-logs
  path.config: "/usr/share/logstash/pipeline/app-logs.conf"
  pipeline.workers: 2

- pipeline.id: syslog
  path.config: "/usr/share/logstash/pipeline/syslog.conf"
  pipeline.workers: 1
```

Update `docker-compose.yml` to mount this file:
```yaml
logstash:
  volumes:
    - ./configs/logstash.yml:/usr/share/logstash/config/logstash.yml:ro
    - ./configs/pipelines.yml:/usr/share/logstash/config/pipelines.yml:ro
    - ./phase-2-log-ingestion/logstash/pipelines:/usr/share/logstash/pipeline:ro
```

---

### 2.2 Nginx Access Log Pipeline

**`logstash/pipelines/nginx.conf`**
```ruby
input {
  beats {
    port  => 5044
    tags  => ["nginx", "access"]
    # Only process events tagged as nginx
    add_field => { "[@metadata][pipeline]" => "nginx" }
  }
}

filter {
  # Only process nginx_access logs from this pipeline
  if [log_type] != "nginx_access" {
    drop { }
  }

  # Parse the Nginx Combined Log Format
  grok {
    match => {
      "message" => '%{IPORHOST:client_ip} - %{DATA:user} \[%{HTTPDATE:request_time}\] "%{WORD:http_method} %{DATA:request_path} HTTP/%{NUMBER:http_version}" %{NUMBER:http_status_code:int} %{NUMBER:response_bytes:int} "%{DATA:referrer}" "%{DATA:user_agent}"'
    }
    tag_on_failure => ["_grok_parse_failure"]
  }

  # Parse the timestamp into @timestamp
  date {
    match => ["request_time", "dd/MMM/yyyy:HH:mm:ss Z"]
    target => "@timestamp"
    remove_field => ["request_time"]
  }

  # Categorize HTTP status codes
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

  # GeoIP enrichment — maps client IP to country/city
  geoip {
    source => "client_ip"
    target => "geoip"
    fields => ["city_name", "country_name", "country_code2", "location"]
  }

  # Parse the User-Agent string into browser/OS/device
  useragent {
    source => "user_agent"
    target => "ua"
  }

  # Extract URL path components
  if [request_path] {
    grok {
      match => { "request_path" => "^%{URIPATH:url_path}(?:\?%{GREEDYDATA:url_query})?" }
    }
  }

  # Clean up — remove raw message if successfully parsed
  if "_grok_parse_failure" not in [tags] {
    mutate {
      remove_field => ["message", "agent", "ecs", "host", "input", "log"]
    }
  }
}

output {
  # Route to the correct index
  elasticsearch {
    hosts    => ["elasticsearch:9200"]
    index    => "nginx-access-%{+YYYY.MM.dd}"
    # Use ILM in Phase 5
  }

  # Debug — uncomment to see parsed output in Logstash logs
  # stdout { codec => rubydebug }
}
```

---

### 2.3 Application JSON Log Pipeline

**`logstash/pipelines/app-logs.conf`**
```ruby
input {
  beats {
    port  => 5044
    tags  => ["application"]
  }
}

filter {
  if [log_type] != "app_json" {
    drop { }
  }

  # Parse JSON application logs
  json {
    source => "message"
    target => "app"
    tag_on_failure => ["_json_parse_failure"]
  }

  # If JSON parsing succeeded, promote key fields to root level
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

  # Parse timestamp from app log (if present)
  if [app][timestamp] {
    date {
      match => ["[app][timestamp]", "ISO8601", "yyyy-MM-dd HH:mm:ss"]
      target => "@timestamp"
      remove_field => ["[app][timestamp]"]
    }
  }

  # Normalize log levels
  if [log_level] {
    mutate {
      uppercase => ["log_level"]
    }
  }

  # Tag slow requests (> 1000ms)
  if [response_time_ms] and [response_time_ms] > 1000 {
    mutate {
      add_tag   => ["slow_request"]
      add_field => { "performance_flag" => "slow" }
    }
  }

  # Tag errors
  if [log_level] == "ERROR" or [log_level] == "FATAL" {
    mutate { add_tag => ["error"] }
  }

  mutate {
    remove_field => ["message", "agent", "ecs", "host", "input"]
  }
}

output {
  elasticsearch {
    hosts => ["elasticsearch:9200"]
    index => "app-logs-%{+YYYY.MM.dd}"
  }
}
```

---

### 2.4 Syslog Pipeline

**`logstash/pipelines/syslog.conf`**
```ruby
input {
  beats {
    port => 5044
    tags => ["syslog"]
  }
}

filter {
  if [log_type] != "syslog" {
    drop { }
  }

  # Parse standard syslog format
  grok {
    match => {
      "message" => "%{SYSLOGTIMESTAMP:syslog_timestamp} %{SYSLOGHOST:syslog_host} %{DATA:syslog_program}(?:\[%{POSINT:syslog_pid}\])?: %{GREEDYDATA:syslog_message}"
    }
    tag_on_failure => ["_syslog_parse_failure"]
  }

  # Parse syslog timestamp
  date {
    match => ["syslog_timestamp", "MMM  d HH:mm:ss", "MMM dd HH:mm:ss"]
    target => "@timestamp"
  }

  # Detect failed SSH login attempts
  if [syslog_program] == "sshd" {
    if [syslog_message] =~ /Failed password/ {
      grok {
        match => {
          "syslog_message" => "Failed password for (?:invalid user )?%{USERNAME:ssh_failed_user} from %{IPORHOST:ssh_source_ip}"
        }
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

  # Detect OOM killer
  if [syslog_message] =~ /Out of memory/ or [syslog_message] =~ /oom-kill/ {
    mutate {
      add_tag   => ["oom_event"]
      add_field => { "system_event" => "oom_kill" }
    }
  }

  # Detect disk full
  if [syslog_message] =~ /No space left on device/ {
    mutate {
      add_tag   => ["disk_full"]
      add_field => { "system_event" => "disk_full" }
    }
  }

  mutate {
    remove_field => ["message", "agent", "ecs", "host", "input"]
  }
}

output {
  elasticsearch {
    hosts => ["elasticsearch:9200"]
    index => "syslog-%{+YYYY.MM.dd}"
  }
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

1. Open `http://<EC2_IP>:5601`
2. Go to **Stack Management → Index Patterns**
3. Create index patterns: `nginx-access-*`, `app-logs-*`, `syslog-*`
4. Go to **Discover** and select your index pattern
5. Try these KQL queries in Discover:

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
