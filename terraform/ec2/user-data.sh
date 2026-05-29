#!/bin/bash

# ==============================================================================
# LOGGING SETUP
# Redirects all outputs and errors to a central log file for easy debugging.
# View live progress on the EC2 instance using: tail -f /var/log/user-data.log
# ==============================================================================
echo "======================================================"
echo "STARTING AUTOMATED ELK STACK CONFIGURATION"
echo "======================================================"

# ==============================================================================
# STEP 1: SYSTEM SYSTEM LEVEL ADJUSTMENTS (CRITICAL FOR ELK)
# Elasticsearch requires higher virtual memory settings to run without crashing.
# ==============================================================================
echo "[1/5] Configuring Linux Virtual Memory for Elasticsearch..."
sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" >> /etc/sysctl.conf

# ==============================================================================
# STEP 2: PREREQUISITE INSTALLATION
# Install common software properties, curl, and git.
# ==============================================================================
echo "[2/5] Updating packages and installing Git..."
apt-get update -y
apt-get install -y git curl apt-transport-https ca-certificates software-properties-common

# ==============================================================================
# STEP 3: INSTALL DOCKER ENGINE & DOCKER COMPOSE
# Most ELK repositories run via Docker Compose to manage components easily.
# ==============================================================================
echo "[3/5] Installing Docker Engine..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://docker.com | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://docker.com $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Start and enable the Docker service daemon
systemctl start docker
systemctl enable docker

# ==============================================================================
# STEP 4: CLONE YOUR TARGET REPOSITORY
# Interpolates the variable passed directly from your Terraform workspace.
# ==============================================================================
echo "[4/5] Cloning ELK Stack repository from: ${project_repo}"
cd /home/ubuntu
git clone "${project_repo}" elk-stack-app

# Fix directory ownership permissions for the ubuntu system user
chown -R ubuntu:ubuntu /home/ubuntu/elk-stack-app

# ==============================================================================
# STEP 5: AUTOMATICALLY DEPLOY THE APPLICATION
# Navigates into your repository and fires up your deployment scripts.
# ==============================================================================
echo "[5/5] Launching ELK Stack services..."
cd /home/ubuntu/elk-stack-app

# Option A: If your repo uses Docker Compose (Recommended)
if [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
    echo "Found docker-compose file. Launching containers..."
    docker compose up -d
# Option B: Fallback if your repo uses a setup shell script instead
elif [ -f "setup.sh" ]; then
    echo "Found setup.sh script. Running custom setup..."
    chmod +x setup.sh
    ./setup.sh
else
    echo "WARNING: Neither docker-compose.yml nor setup.sh was found in your repository root."
fi

echo "======================================================"
echo "ELK STACK SETUP COMPLETE"
echo "======================================================"
