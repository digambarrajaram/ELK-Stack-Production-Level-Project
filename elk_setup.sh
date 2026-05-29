#!/bin/bash

# =============================================================================
# deploy-elk.sh — ELK Stack deploy script
# Run manually after SSH-ing into the server:
#   sudo bash /home/ubuntu/deploy-elk.sh
#
# Safe to re-run — all steps are idempotent.
# Logs written to: /var/log/deploy-elk.log
# =============================================================================

set -euo pipefail

LOG_FILE="/var/log/deploy-elk.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

APP_DIR="/home/ubuntu/elk-stack-app"
CERTS_DIR="${APP_DIR}/security/certs"
ES_IMAGE="docker.elastic.co/elasticsearch/elasticsearch:8.11.0"
ES_URL="https://localhost:9200"

echo "======================================================"
echo "ELK STACK DEPLOY — $(date)"
echo "======================================================"

# ------------------------------------------------------------------------------
# PREFLIGHT checks
# ------------------------------------------------------------------------------
echo ""
echo "[preflight] Checking prerequisites..."

if [ ! -d "$APP_DIR" ]; then
  echo "ERROR: $APP_DIR not found."
  echo "       user-data.sh may not have completed yet."
  echo "       Check: cat /var/log/user-data.log"
  exit 1
fi

if [ ! -f "$APP_DIR/.env" ]; then
  echo "ERROR: $APP_DIR/.env not found."
  echo "       user-data.sh may not have written it yet."
  echo "       Check: cat /var/log/user-data.log"
  exit 1
fi

if ! command -v docker &> /dev/null; then
  echo "ERROR: Docker not found. Check: cat /var/log/user-data.log"
  exit 1
fi

if ! command -v openssl &> /dev/null; then
  echo "ERROR: openssl not found. Install with: apt-get install -y openssl"
  exit 1
fi

if ! command -v jq &> /dev/null; then
  echo "  jq not found — installing..."
  apt-get install -y jq > /dev/null 2>&1
fi

echo "  app dir          : $APP_DIR — OK"
echo "  .env             : found — OK"
echo "  docker           : $(docker --version) — OK"
echo "  openssl          : $(openssl version) — OK"
echo "  vm.max_map_count : $(sysctl -n vm.max_map_count)"

# ------------------------------------------------------------------------------
# STEP 1: Fix .env line endings and load variables
# ------------------------------------------------------------------------------
echo ""
echo "[1/6] Fixing .env and loading environment variables..."

# Strip Windows-style \r carriage returns if present
sed -i 's/\r//' "${APP_DIR}/.env"

# Load all non-comment variables into the current shell
set +u  # temporarily allow unbound vars during source
source "${APP_DIR}/.env"
set -u

# Validate required variables are present and non-empty
REQUIRED_VARS=(ELASTIC_PASSWORD KIBANA_SYSTEM_PASSWORD)
for VAR in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!VAR:-}" ]; then
    echo "ERROR: ${VAR} is not set or empty in .env"
    echo "       Add it to ${APP_DIR}/.env and re-run."
    exit 1
  fi
done

echo "  ELASTIC_PASSWORD       : set — OK"
echo "  KIBANA_SYSTEM_PASSWORD : set — OK"

# ------------------------------------------------------------------------------
# STEP 2: Generate TLS certificates
# ------------------------------------------------------------------------------
echo ""
echo "[2/6] Generating TLS certificates..."

mkdir -p "${CERTS_DIR}"
chown -R ubuntu:ubuntu "${CERTS_DIR}"

if [ ! -f "${CERTS_DIR}/elastic-certificates.p12" ]; then

  echo "  Pulling Elasticsearch image (will be reused by compose)..."
  docker pull "${ES_IMAGE}" || {
    echo "ERROR: Failed to pull ${ES_IMAGE}"
    exit 1
  }

  echo "  Generating CA (elastic-ca.p12)..."
  docker run --rm \
    -v "${CERTS_DIR}:/certs" \
    --user "$(id -u ubuntu):$(id -g ubuntu)" \
    "${ES_IMAGE}" \
    bin/elasticsearch-certutil ca \
      --silent \
      --out /certs/elastic-ca.p12 \
      --pass "" || {
    echo "ERROR: CA generation failed"
    exit 1
  }

  echo "  Generating node certificate (elastic-certificates.p12)..."
  docker run --rm \
    -v "${CERTS_DIR}:/certs" \
    --user "$(id -u ubuntu):$(id -g ubuntu)" \
    "${ES_IMAGE}" \
    bin/elasticsearch-certutil cert \
      --silent \
      --ca /certs/elastic-ca.p12 \
      --ca-pass "" \
      --out /certs/elastic-certificates.p12 \
      --pass "" || {
    echo "ERROR: Node certificate generation failed"
    exit 1
  }

  echo "  Exporting CA to PEM (needed for curl --cacert)..."
  openssl pkcs12 \
    -in "${CERTS_DIR}/elastic-ca.p12" \
    -nokeys \
    -cacerts \
    -out "${CERTS_DIR}/elastic-stack-ca.pem" \
    -passin pass:"" || {
    echo "ERROR: PEM export failed"
    exit 1
  }

  # Kibana expects elastic-stack-ca.p12 by name (set in docker-compose env)
  if [ ! -f "${CERTS_DIR}/elastic-stack-ca.p12" ]; then
    cp "${CERTS_DIR}/elastic-ca.p12" "${CERTS_DIR}/elastic-stack-ca.p12"
    echo "  Copied elastic-ca.p12 → elastic-stack-ca.p12"
  fi

  chown -R ubuntu:ubuntu "${CERTS_DIR}"
  chmod 640 "${CERTS_DIR}"/*.p12
  chmod 644 "${CERTS_DIR}"/*.pem
  echo "  Certificates generated:"
  ls -lh "${CERTS_DIR}"

else
  echo "  Certificates already exist — skipping generation:"
  ls -lh "${CERTS_DIR}"

  # Still export PEM if it's missing (re-run scenario)
  if [ ! -f "${CERTS_DIR}/elastic-stack-ca.pem" ]; then
    echo "  PEM missing — exporting from existing p12..."
    openssl pkcs12 \
      -in "${CERTS_DIR}/elastic-ca.p12" \
      -nokeys \
      -cacerts \
      -out "${CERTS_DIR}/elastic-stack-ca.pem" \
      -passin pass:""
    chmod 644 "${CERTS_DIR}/elastic-stack-ca.pem"
  fi

  if [ ! -f "${CERTS_DIR}/elastic-stack-ca.p12" ]; then
    cp "${CERTS_DIR}/elastic-ca.p12" "${CERTS_DIR}/elastic-stack-ca.p12"
    echo "  Copied elastic-ca.p12 → elastic-stack-ca.p12"
  fi
fi

# ------------------------------------------------------------------------------
# STEP 3: Deploy ELK stack
# ------------------------------------------------------------------------------
echo ""
echo "[3/6] Starting ELK stack..."

cd "$APP_DIR"

if [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
  docker compose up -d || {
    echo "ERROR: docker compose up -d failed"
    echo "       Check: docker compose logs"
    exit 1
  }
elif [ -f "setup.sh" ]; then
  chmod +x setup.sh
  bash setup.sh || {
    echo "ERROR: setup.sh failed"
    exit 1
  }
else
  echo "ERROR: No docker-compose.yml or setup.sh found in $APP_DIR"
  exit 1
fi

# ------------------------------------------------------------------------------
# STEP 4: Wait for Elasticsearch to be healthy
# ------------------------------------------------------------------------------
echo ""
echo "[4/6] Waiting for Elasticsearch to be healthy..."

MAX_ATTEMPTS=30
WAIT_SECONDS=10

for i in $(seq 1 ${MAX_ATTEMPTS}); do
  HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" \
    -u "elastic:${ELASTIC_PASSWORD}" \
    --cacert "${CERTS_DIR}/elastic-stack-ca.pem" \
    "${ES_URL}/_cluster/health" 2>/dev/null || echo "000")

  if [ "${HTTP_CODE}" = "200" ]; then
    echo "  Elasticsearch is up and authenticated (attempt ${i}/${MAX_ATTEMPTS})"
    break
  fi

  if [ "${i}" -eq "${MAX_ATTEMPTS}" ]; then
    echo "ERROR: Elasticsearch not responding after $((MAX_ATTEMPTS * WAIT_SECONDS))s (last HTTP: ${HTTP_CODE})"
    echo "       Check: docker compose logs elasticsearch | tail -40"
    exit 1
  fi

  echo "  Attempt ${i}/${MAX_ATTEMPTS} — HTTP ${HTTP_CODE} — waiting ${WAIT_SECONDS}s..."
  sleep ${WAIT_SECONDS}
done

# Print cluster health
CLUSTER_STATUS=$(curl -sk \
  -u "elastic:${ELASTIC_PASSWORD}" \
  --cacert "${CERTS_DIR}/elastic-stack-ca.pem" \
  "${ES_URL}/_cluster/health" | jq -r '.status')
echo "  Cluster health: ${CLUSTER_STATUS}"

# ------------------------------------------------------------------------------
# STEP 5: Set built-in user passwords
# ------------------------------------------------------------------------------
echo ""
echo "[5/6] Configuring built-in user passwords..."

# kibana_system
echo "  Setting kibana_system password..."
KIBANA_HTTP=$(curl -sk -o /dev/null -w "%{http_code}" \
  -u "elastic:${ELASTIC_PASSWORD}" \
  --cacert "${CERTS_DIR}/elastic-stack-ca.pem" \
  -X POST "${ES_URL}/_security/user/kibana_system/_password" \
  -H "Content-Type: application/json" \
  -d "{\"password\":\"${KIBANA_SYSTEM_PASSWORD}\"}")

if [ "${KIBANA_HTTP}" = "200" ]; then
  echo "  kibana_system password set — OK"
else
  echo "  WARNING: kibana_system password set returned HTTP ${KIBANA_HTTP}"
  echo "           Kibana may fail to connect. Check KIBANA_SYSTEM_PASSWORD in .env"
fi

# logstash_system (if variable is set in .env)
if [ -n "${LOGSTASH_SYSTEM_PASSWORD:-}" ]; then
  echo "  Setting logstash_system password..."
  LS_HTTP=$(curl -sk -o /dev/null -w "%{http_code}" \
    -u "elastic:${ELASTIC_PASSWORD}" \
    --cacert "${CERTS_DIR}/elastic-stack-ca.pem" \
    -X POST "${ES_URL}/_security/user/logstash_system/_password" \
    -H "Content-Type: application/json" \
    -d "{\"password\":\"${LOGSTASH_SYSTEM_PASSWORD}\"}")

  if [ "${LS_HTTP}" = "200" ]; then
    echo "  logstash_system password set — OK"
  else
    echo "  WARNING: logstash_system password returned HTTP ${LS_HTTP}"
  fi
fi

# Restart Kibana so it picks up the new password
echo "  Restarting Kibana to apply new kibana_system password..."
docker compose restart kibana > /dev/null 2>&1

# ------------------------------------------------------------------------------
# STEP 6: Health check — full stack verification
# ------------------------------------------------------------------------------
echo ""
echo "[6/6] Running full stack health check..."

# Wait for Kibana to come back after restart
echo "  Waiting 30s for Kibana to restart..."
sleep 30

echo ""
echo "--- Container status ---"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "--- Elasticsearch ---"
curl -sk \
  -u "elastic:${ELASTIC_PASSWORD}" \
  --cacert "${CERTS_DIR}/elastic-stack-ca.pem" \
  "${ES_URL}/_cluster/health?pretty" | jq '{status: .status, nodes: .number_of_nodes}'

echo ""
echo "--- Kibana ---"
KIBANA_LEVEL=$(curl -sk \
  "http://localhost:5601/api/status" \
  -u "elastic:${ELASTIC_PASSWORD}" 2>/dev/null | jq -r '.status.overall.level // "unreachable"')
echo "  Kibana status: ${KIBANA_LEVEL}"

echo ""
echo "--- Logstash ---"
LS_STATUS=$(curl -sk http://localhost:9600 2>/dev/null | jq -r '.status // "unreachable"')
echo "  Logstash status: ${LS_STATUS}"

echo ""
echo "--- TLS verification ---"
TLS_CODE=$(curl -sk -o /dev/null -w "%{http_code}" "${ES_URL}" 2>/dev/null || echo "000")
if [ "${TLS_CODE}" = "401" ]; then
  echo "  TLS active — unauthenticated request correctly returns 401 — OK"
else
  echo "  WARNING: Unexpected response without credentials: HTTP ${TLS_CODE}"
fi

echo ""
echo "--- Indices ---"
curl -sk \
  -u "elastic:${ELASTIC_PASSWORD}" \
  --cacert "${CERTS_DIR}/elastic-stack-ca.pem" \
  "${ES_URL}/_cat/indices?v&health=green" 2>/dev/null | head -20 || echo "  No indices yet (expected on fresh deploy)"

# Final summary
echo ""
echo "======================================================"
echo "SUMMARY"
echo "======================================================"
echo "  Elasticsearch : ${CLUSTER_STATUS}"
echo "  Kibana        : ${KIBANA_LEVEL}"
echo "  Logstash      : ${LS_STATUS}"

if [ "${CLUSTER_STATUS}" = "green" ] || [ "${CLUSTER_STATUS}" = "yellow" ]; then
  echo ""
  echo "  ELK stack is UP. Access Kibana at: http://$(curl -s ifconfig.me 2>/dev/null || echo '<server-ip>'):5601"
  echo "  Login: elastic / <ELASTIC_PASSWORD from .env>"
else
  echo ""
  echo "  WARNING: Cluster status is ${CLUSTER_STATUS} — check logs:"
  echo "    docker compose logs elasticsearch | tail -40"
fi

echo ""
echo "======================================================"
echo "ELK DEPLOY COMPLETE — $(date)"
echo "Log saved to: ${LOG_FILE}"
echo "======================================================"