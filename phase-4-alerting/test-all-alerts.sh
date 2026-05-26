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
