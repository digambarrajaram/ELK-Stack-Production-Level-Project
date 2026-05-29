#!/bin/bash

# Date: 29 May 2026
# Production-grade ELK Stack Bootstrap Script (Terraform-safe)
# Fixes applied:
#   - All bash ${VAR} references escaped as $${VAR} for Terraform templatefile()
#   - ${project_repo} is the ONLY Terraform-interpolated variable (single $)
#   - Docker group membership handled via 'sg docker' for subprocess
#   - Inner failures surface and abort outer script cleanly
#   - Post-deploy Elasticsearch health check added

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
# TERRAFORM NOTE: This script must be rendered via templatefile(), e.g.:
#   user_data_base64 = base64encode(templatefile("$${path.module}/user-data.sh", {
#     project_repo = var.project_repo
#   }))
#
# Rule: ${project_repo} = Terraform variable  (single $, resolved at plan/apply)
#       $${ANY_BASH_VAR} = bash variable       (double $$, rendered as ${...} at runtime)

PROJECT_REPO="${project_repo}"

if [ -z "$PROJECT_REPO" ]; then
  echo "ERROR: project_repo is empty. Ensure templatefile() is used in Terraform."
  exit 1
fi

echo "Target repository: $PROJECT_REPO"

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

# Remove any stale/incorrect docker repo entries
rm -f /etc/apt/sources.list.d/docker.list

# Add Docker GPG key
install -m 0755 -d /etc/apt/keyrings

if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
fi

chmod a+r /etc/apt/keyrings/docker.gpg

# Capture arch and codename into variables first to avoid any interpolation ambiguity
# FIX: bash vars referenced as $${ARCH} / $${UBUNTU_CODENAME} in templatefile context
#      so Terraform does not try to resolve them as template variables.
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

# Add ubuntu user to docker group
# NOTE: usermod does not activate the group for already-running sessions.
#       Use 'sg docker' in Step 5 to force the group context for subprocesses.
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
# STEP 5: DEPLOY ELK STACK
# ------------------------------------------------------------------------------
echo "[5/5] Deploying ELK Stack..."

cd /home/ubuntu/elk-stack-app

# FIX: 'usermod -aG docker ubuntu' does NOT activate the docker group for
#      subprocesses in this script. 'sg docker' forces the group context,
#      allowing 'docker compose' to run without permission errors.

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

ES_URL="http://localhost:9200"
MAX_ATTEMPTS=30
WAIT_SECONDS=10

for i in $(seq 1 $${MAX_ATTEMPTS}); do
  if curl -s --max-time 5 "$${ES_URL}" > /dev/null 2>&1; then
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

# Print final container status for log visibility
echo ""
echo "--- Docker Container Status ---"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || true

echo "======================================================"
echo "ELK STACK SETUP COMPLETE"
echo "DATE: $(date)"
echo "======================================================"