#!/bin/bash

# =============================================================================
# user-data.sh — EC2 startup script (Terraform templatefile)
# Runs once automatically via cloud-init on first boot.
# Responsibility: system config + Docker install + repo clone + .env write
#
# Escaping rule (applies in code AND comments):
#   Single dollar-brace = Terraform variable, resolved at plan/apply time
#   Double dollar-brace = bash variable, rendered as single dollar-brace at runtime
# =============================================================================

set -euo pipefail

LOG_FILE="/var/log/user-data.log"
exec > "$${LOG_FILE}" 2>&1

echo "======================================================"
echo "EC2 STARTUP — $(date)"
echo "======================================================"

# ------------------------------------------------------------------------------
# PREFLIGHT: Validate Terraform-injected variables
# ------------------------------------------------------------------------------
PROJECT_REPO="${project_repo}"
ENV_FILE_CONTENT='${env_file_content}'
ELASTIC_PASSWORD='${elastic_password}'
KIBANA_PASSWORD='${kibana_password}'

if [ -z "$PROJECT_REPO" ]; then
  echo "ERROR: project_repo is empty. Ensure templatefile() is used in Terraform."
  exit 1
fi

echo "Target repository: $PROJECT_REPO"

# ------------------------------------------------------------------------------
# STEP 1: System settings (Elasticsearch requirement)
# ------------------------------------------------------------------------------
echo "[1/4] Configuring system settings..."

sysctl -w vm.max_map_count=262144
if ! grep -q "vm.max_map_count=262144" /etc/sysctl.conf; then
  echo "vm.max_map_count=262144" >> /etc/sysctl.conf
fi
echo "vm.max_map_count = $(sysctl -n vm.max_map_count)"

# ------------------------------------------------------------------------------
# STEP 2: Install prerequisites
# ------------------------------------------------------------------------------
echo "[2/4] Installing prerequisites..."

apt-get update -y
apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  git

# ------------------------------------------------------------------------------
# STEP 3: Install Docker
# ------------------------------------------------------------------------------
echo "[3/4] Installing Docker..."

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
usermod -aG docker ubuntu

if ! command -v docker &> /dev/null; then
  echo "ERROR: Docker installation failed"
  exit 1
fi
echo "Docker installed: $(docker --version)"

# ------------------------------------------------------------------------------
# STEP 4: Clone repo and write .env
# ------------------------------------------------------------------------------
echo "[4/4] Cloning repository and writing .env..."

cd /home/ubuntu

if [ -d "elk-stack-app" ]; then
  echo "Repo already exists, pulling latest..."
  cd elk-stack-app
  git pull || { echo "ERROR: git pull failed"; exit 1; }
else
  git clone "$PROJECT_REPO" elk-stack-app || {
    echo "ERROR: git clone failed for: $PROJECT_REPO"
    exit 1
  }
fi

chown -R ubuntu:ubuntu /home/ubuntu/elk-stack-app
cd /home/ubuntu/elk-stack-app

# Write .env — Option A (local file copy) or Option B (Terraform variables)
if [ -n "$ENV_FILE_CONTENT" ]; then
  echo "Writing .env from Terraform file content (Option A)..."
  printf '%s\n' "$ENV_FILE_CONTENT" > .env

elif [ -n "$ELASTIC_PASSWORD" ] && [ -n "$KIBANA_PASSWORD" ]; then
  echo "Building .env from Terraform variables (Option B)..."
  if [ ! -f ".env.example" ]; then
    echo "ERROR: .env.example not found in repo"
    exit 1
  fi
  cp .env.example .env
  sed -i "s|^ELASTIC_PASSWORD=.*|ELASTIC_PASSWORD=$${ELASTIC_PASSWORD}|" .env
  sed -i "s|^KIBANA_SYSTEM_PASSWORD=.*|KIBANA_SYSTEM_PASSWORD=$${KIBANA_PASSWORD}|" .env

else
  echo "ERROR: No .env content provided. Use Option A or Option B in Terraform."
  exit 1
fi

chown ubuntu:ubuntu .env
chmod 600 .env

echo ".env keys written:"
grep "^[A-Z]" .env | cut -d'=' -f1 | sed 's/^/  /'

# Place the ELK deploy script where ubuntu user can easily run it
cp /var/lib/cloud/instance/scripts/part-001 /home/ubuntu/deploy-elk.sh 2>/dev/null || true

echo ""
echo "======================================================"
echo "EC2 STARTUP COMPLETE — $(date)"
echo "Server is ready. SSH in and run:"
echo "  sudo bash /home/ubuntu/deploy-elk.sh"
echo "======================================================"