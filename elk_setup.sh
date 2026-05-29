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

echo "======================================================"
echo "ELK STACK DEPLOY — $(date)"
echo "======================================================"

# ------------------------------------------------------------------------------
# PREFLIGHT checks
# ------------------------------------------------------------------------------
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

echo "  app dir   : $APP_DIR — OK"
echo "  .env      : found — OK"
echo "  docker    : $(docker --version) — OK"
echo "  vm.max_map_count : $(sysctl -n vm.max_map_count)"

# ------------------------------------------------------------------------------
# STEP 1: Generate TLS certificates
# ------------------------------------------------------------------------------
echo ""
echo "[1/3] Generating TLS certificates..."

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
    --user "$(id -u):$(id -g)" \
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
    --user "$(id -u):$(id -g)" \
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

  chown -R ubuntu:ubuntu "${CERTS_DIR}"
  chmod 640 "${CERTS_DIR}"/*.p12
  echo "  Certificates generated:"
  ls -lh "${CERTS_DIR}"

else
  echo "  Certificates already exist, skipping:"
  ls -lh "${CERTS_DIR}"
fi

# ------------------------------------------------------------------------------
# STEP 2: Deploy ELK stack
# ------------------------------------------------------------------------------
echo ""
echo "[2/3] Starting ELK stack..."

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
# STEP 3: Health check + password verification
# ------------------------------------------------------------------------------
echo ""
echo "[3/3] Waiting for Elasticsearch..."

ES_URL="https://localhost:9200"
MAX_ATTEMPTS=30
WAIT_SECONDS=10

for i in $(seq 1 ${MAX_ATTEMPTS}); do
  if curl -sk --max-time 5 "${ES_URL}" > /dev/null 2>&1; then
    echo "  Elasticsearch is up (attempt ${i}/${MAX_ATTEMPTS})"
    break
  fi
  if [ "${i}" -eq "${MAX_ATTEMPTS}" ]; then
    echo "  WARNING: ES not responding after $((MAX_ATTEMPTS * WAIT_SECONDS))s"
    echo "  Check: docker logs elasticsearch | tail -30"
  else
    echo "  Attempt ${i}/${MAX_ATTEMPTS} — waiting ${WAIT_SECONDS}s..."
    sleep ${WAIT_SECONDS}
  fi
done

echo ""
echo "--- Container status ---"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "--- Verifying ELASTIC_PASSWORD from .env ---"
STORED_PASSWORD=$(grep "^ELASTIC_PASSWORD=" "${APP_DIR}/.env" \
  | cut -d'=' -f2- | tr -d '[:space:]')

if [ -z "${STORED_PASSWORD}" ]; then
  echo "WARNING: ELASTIC_PASSWORD is blank in .env"
  echo "         Check: docker logs elasticsearch | grep -i password"
else
  sleep 15
  CURL_FMT=$(printf '%%s' '%' '{http_code}')
  HTTP_CODE=$(curl -sk -o /dev/null -w "${CURL_FMT}" \
    -u "elastic:${STORED_PASSWORD}" \
    "${ES_URL}/_cluster/health" 2>/dev/null || echo "000")

  if [ "${HTTP_CODE}" = "200" ]; then
    echo "SUCCESS: ELASTIC_PASSWORD from .env is active (HTTP ${HTTP_CODE})"
  elif [ "${HTTP_CODE}" = "401" ]; then
    echo "WARNING: HTTP 401 — password mismatch. ES may have auto-generated a password."
    echo "  Fix (wipes data — fresh instance only):"
    echo "    cd ${APP_DIR} && docker compose down -v && docker compose up -d"
  elif [ "${HTTP_CODE}" = "000" ]; then
    echo "WARNING: Could not reach ES. Still initialising?"
    echo "  Retry: curl -sk -u elastic:<password> ${ES_URL}/_cluster/health"
  else
    echo "WARNING: Unexpected HTTP ${HTTP_CODE}"
    echo "  Check: docker logs elasticsearch | tail -20"
  fi
fi

echo ""
echo "======================================================"
echo "ELK DEPLOY COMPLETE — $(date)"
echo "Log saved to: ${LOG_FILE}"
echo "======================================================"