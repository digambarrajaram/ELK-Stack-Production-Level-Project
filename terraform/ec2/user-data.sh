#!/bin/bash

# Date: 29 May 2026
# Production-grade ELK Stack Bootstrap Script (Terraform-safe)
#
# .env delivery strategy (two options, pick ONE in Terraform):
#
#   OPTION A — local file copy (preferred, cleanest):
#     In main.tf, add a second templatefile for the .env:
#       env_file_content = file("$${path.module}/.env")
#     The script writes it directly from the Terraform-injected variable.
#     Keep your local .env in the ec2/ folder, gitignored.
#
#   OPTION B — Terraform variables (fallback, no local .env file):
#     Pass elastic_password and kibana_password as Terraform variables.
#     The script builds the .env from those two values.
#     Store passwords in terraform.tfvars (gitignored).
#
# Escaping rule — applies in code AND comments:
#   Single dollar-brace  = Terraform variable, resolved at plan/apply
#   Double dollar-brace  = bash variable, rendered as single dollar-brace at runtime

set -euo pipefail

# ------------------------------------------------------------------------------
# LOGGING SETUP
# ------------------------------------------------------------------------------
LOG_FILE="/var/log/user-data.log"
exec > "$${LOG_FILE}" 2>&1

echo "======================================================"
echo "STARTING AUTOMATED ELK STACK CONFIGURATION"
echo "DATE: $(date)"
echo "======================================================"

# ------------------------------------------------------------------------------
# PREFLIGHT: Validate required Terraform-injected variables
# ------------------------------------------------------------------------------
PROJECT_REPO="${project_repo}"

if [ -z "$PROJECT_REPO" ]; then
  echo "ERROR: project_repo is empty. Ensure templatefile() is used in Terraform."
  exit 1
fi

echo "Target repository: $PROJECT_REPO"

# Detect which .env delivery option is in use.
# Terraform renders this file — if env_file_content was passed, it will be
# non-empty here. If elastic_password was passed instead, use that path.
ENV_FILE_CONTENT='${env_file_content}'
ELASTIC_PASSWORD='${elastic_password}'
KIBANA_PASSWORD='${kibana_password}'

# ------------------------------------------------------------------------------
# STEP 1: SYSTEM LEVEL SETTINGS (ELASTICSEARCH REQUIREMENT)
# ------------------------------------------------------------------------------
echo "[1/5] Configuring Linux Virtual Memory..."
sysctl -w vm.max_map_count=262144

if ! grep -q "vm.max_map_count=262144" /etc/sysctl.conf; then
  echo "vm.max_map_count=262144" >> /etc/sysctl.conf
fi

echo "vm.max_map_count set to: $(sysctl -n vm.max_map_count)"

# ------------------------------------------------------------------------------
# STEP 2: INSTALL PREREQUISITES
# ------------------------------------------------------------------------------
echo "[2/5] Installing prerequisites..."
apt-get update -y
apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  git

# ------------------------------------------------------------------------------
# STEP 3: INSTALL DOCKER
# ------------------------------------------------------------------------------
echo "[3/5] Installing Docker..."

rm -f /etc/apt/sources.list.d/docker.list
install -m 0755 -d /etc/apt/keyrings

if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
fi

chmod a+r /etc/apt/keyrings/docker.gpg

ARCH=$(dpkg --print-architecture)
UBUNTU_CODENAME=$(lsb_release -cs)

echo "deb [arch=$${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $${UBUNTU_CODENAME} stable" \
> /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

systemctl enable docker
systemctl start docker

# Group membership does not activate for already-running processes.
# Use 'sg docker' in Step 5 to force the group context for subprocesses.
usermod -aG docker ubuntu

if ! command -v docker &> /dev/null; then
  echo "ERROR: Docker installation failed — 'docker' not found in PATH"
  exit 1
fi

echo "Docker installed successfully: $(docker --version)"

# ------------------------------------------------------------------------------
# STEP 4: CLONE REPOSITORY
# ------------------------------------------------------------------------------
echo "[4/5] Cloning ELK Stack repository..."

cd /home/ubuntu

if [ -d "elk-stack-app" ]; then
  echo "Repository already exists. Pulling latest..."
  cd elk-stack-app
  git pull || {
    echo "ERROR: git pull failed"
    exit 1
  }
else
  git clone "$PROJECT_REPO" elk-stack-app || {
    echo "ERROR: git clone failed for repo: $PROJECT_REPO"
    exit 1
  }
fi

chown -R ubuntu:ubuntu /home/ubuntu/elk-stack-app

# ------------------------------------------------------------------------------
# PRE-DEPLOY: Write .env file
# ------------------------------------------------------------------------------
echo "Writing .env file..."

cd /home/ubuntu/elk-stack-app

if [ -n "$ENV_FILE_CONTENT" ]; then
  # OPTION A: Full .env content was passed in via Terraform file() function.
  # Write it exactly as provided — no sed substitution needed.
  echo "Using .env content from Terraform (Option A: local file copy)"
  printf '%s\n' "$ENV_FILE_CONTENT" > .env

elif [ -n "$ELASTIC_PASSWORD" ] && [ -n "$KIBANA_PASSWORD" ]; then
  # OPTION B: Individual passwords passed as Terraform variables.
  # Build .env from .env.example, substituting the password placeholders.
  echo "Building .env from Terraform variables (Option B: variable injection)"

  if [ ! -f ".env.example" ]; then
    echo "ERROR: .env.example not found in repo — cannot build .env"
    exit 1
  fi


  # Replace password lines — handles both blank and placeholder values
  sed -i "s|^ELASTIC_PASSWORD=.*|ELASTIC_PASSWORD=$${ELASTIC_PASSWORD}|" .env
  sed -i "s|^KIBANA_SYSTEM_PASSWORD=.*|KIBANA_SYSTEM_PASSWORD=$${KIBANA_PASSWORD}|" .env

else
  # Neither option configured — fail with clear guidance
  echo "ERROR: No .env configuration found."
  echo "  Option A: pass env_file_content = file(\"\$${path.module}/.env\") in templatefile()"
  echo "  Option B: pass elastic_password and kibana_password as Terraform variables"
  exit 1
fi

# Lock down .env — contains credentials
chown ubuntu:ubuntu .env
chmod 600 .env

echo ".env written successfully:"
# Print keys only, never values
grep "^[A-Z]" .env | cut -d'=' -f1 | sed 's/^/  /'

# ------------------------------------------------------------------------------
# PRE-DEPLOY: Generate TLS certificates for Elasticsearch xpack security
# ------------------------------------------------------------------------------
# The repo's elasticsearch.yml has xpack.security.transport.ssl enabled and
# expects a PKCS12 keystore at configs/certs/elastic-certificates.p12.
# That file must exist before Elasticsearch starts or it fatal-exits with:
#   "failed to load SSL configuration [xpack.security.transport.ssl]"
#
# We use the official Elasticsearch Docker image itself to generate the certs —
# no extra tooling needed. Two steps:
#   1. elasticsearch-certutil ca   → elastic-ca.p12      (self-signed CA)
#   2. elasticsearch-certutil cert → elastic-certificates.p12  (node cert)
# Both use empty passphrases to avoid needing keystore.password in config.
# ------------------------------------------------------------------------------
echo "Generating Elasticsearch TLS certificates..."

APP_DIR="/home/ubuntu/elk-stack-app"
CERTS_DIR="$${APP_DIR}/configs/certs"

mkdir -p "$${CERTS_DIR}"
chown -R ubuntu:ubuntu "$${CERTS_DIR}"

if [ ! -f "$${CERTS_DIR}/elastic-certificates.p12" ]; then

  ES_IMAGE="docker.elastic.co/elasticsearch/elasticsearch:8.11.0"

  echo "Pulling Elasticsearch image for cert generation (reused by compose)..."
  docker pull "$${ES_IMAGE}" || {
    echo "ERROR: Failed to pull Elasticsearch image"
    exit 1
  }

  echo "Generating CA (elastic-ca.p12)..."
  docker run --rm \
    -v "$${CERTS_DIR}:/certs" \
    --user "$(id -u):$(id -g)" \
    "$${ES_IMAGE}" \
    bin/elasticsearch-certutil ca \
      --silent \
      --out /certs/elastic-ca.p12 \
      --pass "" || {
    echo "ERROR: CA generation failed"
    exit 1
  }

  echo "Generating node certificate (elastic-certificates.p12)..."
  docker run --rm \
    -v "$${CERTS_DIR}:/certs" \
    --user "$(id -u):$(id -g)" \
    "$${ES_IMAGE}" \
    bin/elasticsearch-certutil cert \
      --silent \
      --ca /certs/elastic-ca.p12 \
      --ca-pass "" \
      --out /certs/elastic-certificates.p12 \
      --pass "" || {
    echo "ERROR: Node certificate generation failed"
    exit 1
  }

  chown -R ubuntu:ubuntu "$${CERTS_DIR}"
  chmod 640 "$${CERTS_DIR}"/*.p12

  echo "Certificates generated successfully:"
  ls -lh "$${CERTS_DIR}"

else
  echo "Certificates already exist, skipping generation:"
  ls -lh "$${CERTS_DIR}"
fi

# ------------------------------------------------------------------------------
# STEP 5: DEPLOY ELK STACK
# ------------------------------------------------------------------------------
echo "[5/5] Deploying ELK Stack..."

cd /home/ubuntu/elk-stack-app

if [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
  echo "Starting services using Docker Compose..."
  sudo -u ubuntu sg docker -c "cd /home/ubuntu/elk-stack-app && docker compose up -d" || {
    echo "ERROR: 'docker compose up -d' failed"
    exit 1
  }
elif [ -f "setup.sh" ]; then
  echo "Running setup.sh..."
  chmod +x setup.sh
  sudo -u ubuntu sg docker -c "cd /home/ubuntu/elk-stack-app && bash setup.sh" || {
    echo "ERROR: setup.sh failed"
    exit 1
  }
else
  echo "ERROR: No deployment file found (docker-compose.yml / docker-compose.yaml / setup.sh)"
  exit 1
fi

# ------------------------------------------------------------------------------
# POST-DEPLOY: ELASTICSEARCH HEALTH CHECK
# ------------------------------------------------------------------------------
echo "Waiting for Elasticsearch to become ready..."

ES_URL="https://localhost:9200"
MAX_ATTEMPTS=30
WAIT_SECONDS=10

for i in $(seq 1 $${MAX_ATTEMPTS}); do
  if curl -sk --max-time 5 "$${ES_URL}" > /dev/null 2>&1; then
    echo "Elasticsearch is up at $${ES_URL} (attempt $${i}/$${MAX_ATTEMPTS})"
    break
  fi

  if [ "$${i}" -eq "$${MAX_ATTEMPTS}" ]; then
    echo "WARNING: Elasticsearch did not respond after $(( MAX_ATTEMPTS * WAIT_SECONDS ))s."
    echo "Containers may still be initialising. Check: docker compose logs"
  else
    echo "Attempt $${i}/$${MAX_ATTEMPTS} — not ready, retrying in $${WAIT_SECONDS}s..."
    sleep $${WAIT_SECONDS}
  fi
done

echo ""
echo "--- Docker Container Status ---"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || true

# ------------------------------------------------------------------------------
# POST-DEPLOY: VERIFY ELASTIC PASSWORD FROM .env WAS ACCEPTED
# ------------------------------------------------------------------------------
# ES reads ELASTIC_PASSWORD from .env on FIRST boot only and sets the built-in
# elastic superuser password. After that it is stored in the data volume and
# .env is no longer consulted for auth. This check confirms your custom password
# works before you need it — catching a blank/wrong password now, not later.
echo ""
echo "--- Verifying Elastic password from .env ---"

# Read the password that was written to .env
STORED_PASSWORD=$(grep "^ELASTIC_PASSWORD=" /home/ubuntu/elk-stack-app/.env \
  | cut -d'=' -f2- | tr -d '[:space:]')

if [ -z "$${STORED_PASSWORD}" ]; then
  echo "WARNING: ELASTIC_PASSWORD is blank in .env — Elasticsearch may have"
  echo "         started with no auth or a randomly generated password."
  echo "         Check: docker logs elasticsearch | grep -i 'password'"
else
  # Wait a little longer for ES to fully initialise security before testing
  sleep 15

  HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" \
    -u "elastic:$${STORED_PASSWORD}" \
    https://localhost:9200/_cluster/health 2>/dev/null || echo "000")

  if [ "$${HTTP_CODE}" = "200" ]; then
    echo "SUCCESS: Authenticated with your custom ELASTIC_PASSWORD (HTTP $${HTTP_CODE})"
    echo "         Your password from .env is active and working."
  elif [ "$${HTTP_CODE}" = "401" ]; then
    echo "WARNING: Password verification returned HTTP 401 — wrong credentials."
    echo "         This usually means ELASTIC_PASSWORD in .env was blank when"
    echo "         Elasticsearch first started, so ES auto-generated a password."
    echo "         Fix: stop stack, delete the ES data volume, and restart:"
    echo "           cd /home/ubuntu/elk-stack-app"
    echo "           docker compose down -v"
    echo "           docker compose up -d"
  elif [ "$${HTTP_CODE}" = "000" ]; then
    echo "WARNING: Could not reach Elasticsearch for password check."
    echo "         ES may still be initialising — check manually in 2 mins:"
    echo "           curl -sk -u elastic:<your-password> https://localhost:9200/_cluster/health"
  else
    echo "WARNING: Unexpected HTTP $${HTTP_CODE} during password verification."
    echo "         Check: docker logs elasticsearch | tail -20"
  fi
fi

echo "======================================================"
echo "ELK STACK SETUP COMPLETE"
echo "DATE: $(date)"
echo "======================================================"