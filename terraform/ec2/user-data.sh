```bash
#!/bin/bash

# Exit immediately if a command exits with non-zero status
set -euo pipefail

# Logging
LOG_FILE="/var/log/user-data.log"
exec > >(tee -a ${LOG_FILE}) 2>&1

echo "======================================================"
echo "STARTING AUTOMATED ELK STACK CONFIGURATION"
echo "======================================================"

# ------------------------------------------------------------------------------
# STEP 1: SYSTEM LEVEL SETTINGS (ELASTICSEARCH REQUIREMENT)
# ------------------------------------------------------------------------------
echo "[1/5] Configuring Linux Virtual Memory..."
sysctl -w vm.max_map_count=262144

if ! grep -q "vm.max_map_count=262144" /etc/sysctl.conf; then
  echo "vm.max_map_count=262144" >> /etc/sysctl.conf
fi

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
# STEP 3: INSTALL DOCKER (FIXED + PRODUCTION SAFE)
# ------------------------------------------------------------------------------
echo "[3/5] Installing Docker..."

# Remove wrong repo if exists
rm -f /etc/apt/sources.list.d/docker.list

# Add Docker GPG key
install -m 0755 -d /etc/apt/keyrings

if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
fi

chmod a+r /etc/apt/keyrings/docker.gpg

# Add correct Docker repo
ARCH=$(dpkg --print-architecture)
CODENAME=$(lsb_release -cs)

echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu ${CODENAME} stable" \
> /etc/apt/sources.list.d/docker.list

# Install Docker
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Start Docker
systemctl enable docker
systemctl start docker

# Add ubuntu user to docker group
usermod -aG docker ubuntu

# Validate Docker installation
if ! command -v docker &> /dev/null; then
  echo "ERROR: Docker installation failed"
  exit 1
fi

echo "Docker installed successfully: $(docker --version)"

# ------------------------------------------------------------------------------
# STEP 4: CLONE REPOSITORY
# ------------------------------------------------------------------------------
echo "[4/5] Cloning ELK Stack repository..."

cd /home/ubuntu

if [ -d "elk-stack-app" ]; then
  echo "Repo already exists. Pulling latest changes..."
  cd elk-stack-app
  git pull
else
  git clone "${project_repo}" elk-stack-app
fi

chown -R ubuntu:ubuntu /home/ubuntu/elk-stack-app

# ------------------------------------------------------------------------------
# STEP 5: DEPLOY ELK STACK
# ------------------------------------------------------------------------------
echo "[5/5] Deploying ELK Stack..."

cd /home/ubuntu/elk-stack-app

# Run as ubuntu user to avoid permission issues
sudo -u ubuntu bash << 'EOF'

cd /home/ubuntu/elk-stack-app

if [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
    echo "Starting services using Docker Compose..."
    docker compose up -d
elif [ -f "setup.sh" ]; then
    echo "Running setup.sh..."
    chmod +x setup.sh
    ./setup.sh
else
    echo "ERROR: No deployment file found!"
    exit 1
fi

EOF

echo "======================================================"
echo "ELK STACK SETUP COMPLETE"
echo "======================================================"
```
