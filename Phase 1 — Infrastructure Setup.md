# Phase 1 — Infrastructure Setup

> **Goal:** Provision an AWS EC2 instance with Terraform, install Docker, and bring up the full ELK stack using Docker Compose.  
> **Time estimate:** 2–3 hours  
> **What you'll learn:** Terraform basics, Docker Compose multi-service orchestration, ELK component roles

---

## 📐 What We're Building

```
Your laptop
    │
    │  terraform apply
    ▼
AWS EC2 (t3.medium, Ubuntu 22.04)
    │
    │  docker compose up
    ▼
┌─────────────────────────────────────┐
│  Elasticsearch  :9200               │
│  Kibana         :5601               │
│  Logstash       :5044 / 9600        │
│  Filebeat       (agent, no port)    │
└─────────────────────────────────────┘
```

---

## Step 1 — Provision EC2 with Terraform

### 1.1 Create the Terraform files

**`terraform/main.tf`**
```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Security Group — allow SSH, Kibana, ES, Logstash
resource "aws_security_group" "elk_sg" {
  name        = "elk-stack-sg"
  description = "ELK Stack security group"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Restrict to your IP in production
  }

  ingress {
    description = "Kibana"
    from_port   = 5601
    to_port     = 5601
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Elasticsearch"
    from_port   = 9200
    to_port     = 9200
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Logstash Beats"
    from_port   = 5044
    to_port     = 5044
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "elk-stack-sg"
    Project = "elk-stack"
  }
}

# EC2 Instance
resource "aws_instance" "elk_server" {
  ami                    = "ami-0c02fb55956c7d316"  # Ubuntu 22.04 us-east-1
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.elk_sg.id]

  root_block_device {
    volume_size = 30  # GB — ELK needs storage for indices
    volume_type = "gp3"
  }

  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y docker.io docker-compose-plugin git

    # Allow docker without sudo
    usermod -aG docker ubuntu

    # Set vm.max_map_count required by Elasticsearch
    echo "vm.max_map_count=262144" >> /etc/sysctl.conf
    sysctl -w vm.max_map_count=262144

    # Clone your repo (update URL after pushing to GitHub)
    # git clone https://github.com/YOUR_USERNAME/elk-stack-project.git /home/ubuntu/elk-stack
  EOF

  tags = {
    Name    = "elk-stack-server"
    Project = "elk-stack"
  }
}
```

**`terraform/variables.tf`**
```hcl
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type (t3.medium minimum for ELK)"
  type        = string
  default     = "t3.medium"
}

variable "key_name" {
  description = "Name of your EC2 key pair"
  type        = string
}
```

**`terraform/outputs.tf`**
```hcl
output "elk_server_public_ip" {
  description = "Public IP of the ELK server"
  value       = aws_instance.elk_server.public_ip
}

output "kibana_url" {
  description = "Kibana dashboard URL"
  value       = "http://${aws_instance.elk_server.public_ip}:5601"
}

output "elasticsearch_url" {
  description = "Elasticsearch API URL"
  value       = "http://${aws_instance.elk_server.public_ip}:9200"
}
```

### 1.2 Apply Terraform

```bash
cd terraform/

# Initialize providers
terraform init

# Preview what will be created
terraform plan -var="key_name=your-key-pair-name"

# Create the EC2 instance
terraform apply -var="key_name=your-key-pair-name"

# Note the output IP address
# kibana_url = "http://X.X.X.X:5601"
```

### 1.3 SSH into the instance

```bash
ssh -i ~/.ssh/your-key.pem ubuntu@<EC2_PUBLIC_IP>
```

---

## Step 2 — Configure ELK Components

### 2.1 Elasticsearch config

**`configs/elasticsearch.yml`**
```yaml
cluster.name: elk-production
node.name: elk-node-1

# Network
network.host: 0.0.0.0
http.port: 9200

# Discovery (single-node for this project)
discovery.type: single-node

# Memory lock (prevents swapping)
bootstrap.memory_lock: true

# Security — disable for Phase 1, enable in Phase 5
xpack.security.enabled: false
xpack.security.enrollment.enabled: false

# Paths
path.data: /usr/share/elasticsearch/data
path.logs: /usr/share/elasticsearch/logs
```

### 2.2 Kibana config

**`configs/kibana.yml`**
```yaml
server.host: "0.0.0.0"
server.port: 5601
server.name: "elk-kibana"

# Point to Elasticsearch
elasticsearch.hosts: ["http://elasticsearch:9200"]

# Logging
logging.appenders.file.type: file
logging.appenders.file.fileName: /var/log/kibana/kibana.log
logging.appenders.file.layout.type: json
logging.root.appenders: [default, file]
```

### 2.3 Logstash config

**`configs/logstash.yml`**
```yaml
# Logstash 8.x — api.http.* keys replace the 7.x http.host / http.port
api.http.host: "0.0.0.0"
api.http.port: 9600

# Logging (set to info once stable; debug is noisy)
log.level: info

# Pipeline settings (also set per-pipeline in pipelines.yml, but useful as defaults)
pipeline.workers: 2
pipeline.batch.size: 125
pipeline.batch.delay: 50

# X-Pack monitoring (push metrics to Elasticsearch — disabled here, use Stack Monitoring in Kibana instead)
xpack.monitoring.enabled: false
```

---

## Step 3 — Docker Compose

**`docker-compose.yml`**
```yaml
version: "3.8"

services:

  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.11.0
    container_name: elasticsearch
    environment:
      - discovery.type=single-node
      - ES_JAVA_OPTS=-Xms1g -Xmx1g
      - xpack.security.enabled=false
      - xpack.security.enrollment.enabled=false
    ulimits:
      memlock:
        soft: -1
        hard: -1
    volumes:
      - es-data:/usr/share/elasticsearch/data
      - ./configs/elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml:ro
    ports:
      - "9200:9200"
      - "9300:9300"
    networks:
      - elk-net
    healthcheck:
      test: ["CMD-SHELL", "curl -s http://localhost:9200/_cluster/health | grep -q '\"status\":\"green\"\\|\"status\":\"yellow\"'"]
      interval: 30s
      timeout: 10s
      retries: 5
    deploy:
      resources:
        limits:
          memory: 2g

  logstash:
    image: docker.elastic.co/logstash/logstash:8.11.0
    container_name: logstash
    volumes:
      - ./configs/logstash.yml:/usr/share/logstash/config/logstash.yml:ro
      - ./configs/pipelines.yml:/usr/share/logstash/config/pipelines.yml:ro
      # Phase 2: Log ingestion pipelines will be added here
      # - ./phase-2-log-ingestion/logstash/pipelines:/usr/share/logstash/pipeline:ro
    ports:
      - "5044:5044"    # Beats input (used in Phase 2)
      - "5000:5000"    # TCP input
      - "9600:9600"    # Logstash monitoring API
    networks:
      - elk-net
    depends_on:
      elasticsearch:
        condition: service_healthy
    environment:
      # FIX 1: Increased from 512m to 1g — geoip + useragent + grok filters
      # need headroom; 512m caused the arraycopy JVM crash and connection resets.
      - LS_JAVA_OPTS=-Xms1g -Xmx1g
    deploy:
      resources:
        limits:
          # FIX 2: Was "1 g" (with a space) — Docker couldn't parse this correctly.
          # Must be "1500m" or "1.5g" with no space. Set to 1500m to give the
          # 1g JVM heap room for off-heap (network buffers, metaspace, etc.).
          memory: 1500m

  kibana:
    image: docker.elastic.co/kibana/kibana:8.11.0
    container_name: kibana
    user: root
    command: kibana --allow-root
    volumes:
      - ./configs/kibana.yml:/usr/share/kibana/config/kibana.yml:ro
    ports:
      - "5601:5601"
    networks:
      - elk-net
    depends_on:
      elasticsearch:
        condition: service_healthy
    environment:
      - NODE_OPTIONS="--max-old-space-size=512"
    deploy:
      resources:
        limits:
          memory: 800m

  filebeat:
    image: docker.elastic.co/beats/filebeat:8.11.0
    container_name: filebeat
    user: root
    volumes:
      - ./phase-2-log-ingestion/filebeat/filebeat.yml:/usr/share/filebeat/filebeat.yml:ro
      - /var/log:/var/log:ro
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - filebeat-data:/usr/share/filebeat/data
    networks:
      - elk-net
    depends_on:
      - logstash
    command: filebeat -e -strict.perms=false
    deploy:
      resources:
        limits:
          memory: 250m


volumes:
  es-data:
    driver: local
  filebeat-data:
    driver: local

networks:
  elk-net:
    driver: bridge
```

---

## Step 4 — Start the Stack

```bash
# On your EC2 instance, clone your repo and go to project root
cd elk-stack-project/

# Set vm.max_map_count (required by ES, persists across reboots)
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf

# Pull all images first (saves time)
docker compose pull

# Start in detached mode
docker compose up -d

# Watch the startup logs
docker compose logs -f

# Check all containers are running
docker compose ps
```

---

## Step 5 — Verify Everything Works

```bash
# 1. Check Elasticsearch health
curl -X GET "http://localhost:9200/_cluster/health?pretty"
# Expected: "status" : "green" or "yellow"

# 2. Check Elasticsearch is indexing
curl -X GET "http://localhost:9200/_cat/indices?v"

# 3. Check Logstash is running
curl -X GET "http://localhost:9600/?pretty"

# 4. Check Kibana
curl -I http://localhost:5601
# Expected: HTTP/1.1 302 Found

# 5. Check all container statuses
docker compose ps
```

**Open Kibana in browser:**
```
http://<EC2_PUBLIC_IP>:5601
```

---

## ✅ Phase 1 Checklist

- [ ] Terraform successfully provisions EC2 instance
- [ ] All 4 containers (ES, Logstash, Kibana, Filebeat) show `Up` in `docker compose ps`
- [ ] `curl localhost:9200/_cluster/health` returns green/yellow
- [ ] Kibana loads in the browser at `:5601`
- [ ] `docker compose logs elasticsearch` shows no errors

---

## Step 6 — Phase 1 vs Phase 2: Understanding the Architecture Progression

### Phase 1: Infrastructure Only
In Phase 1, we:
- ✅ Provision EC2 instance with Terraform
- ✅ Install Docker and Docker Compose
- ✅ Start 4 containers: Elasticsearch, Logstash, Kibana, Filebeat
- ✅ Verify all services are running and healthy

**What we DON'T do in Phase 1:**
- ❌ Configure log pipelines (Logstash filters/parsing)
- ❌ Create Filebeat inputs or outputs
- ❌ Ingest real logs

### Phase 2: Log Ingestion Pipelines
In Phase 2, we:
- ✅ Configure Filebeat to watch log files
- ✅ Write Logstash pipelines (Grok filters, enrichment)
- ✅ Create combined.conf pipeline
- ✅ Start ingesting and parsing logs

**Phase 2 Update to docker-compose.yml:**
```diff
  logstash:
    volumes:
      - ./configs/logstash.yml:/usr/share/logstash/config/logstash.yml:ro
      - ./configs/pipelines.yml:/usr/share/logstash/config/pipelines.yml:ro
+     - ./phase-2-log-ingestion/logstash/pipelines:/usr/share/logstash/pipeline:ro
```

When you're ready for Phase 2, uncomment that volume mount line and restart:
```bash
docker compose down
docker compose up -d
```

---

## Complete Configuration Files (Reference)

### Elasticsearch Configuration

**`configs/elasticsearch.yml`**
```yaml
cluster.name: elk-production
node.name: elk-node-1

# Network
network.host: 0.0.0.0
http.port: 9200

# Discovery (single-node for this project)
discovery.type: single-node

# Memory lock (prevents swapping)
bootstrap.memory_lock: true

# Security — disable for Phase 1, enable in Phase 5
xpack.security.enabled: false
xpack.security.enrollment.enabled: false

# Paths
path.data: /usr/share/elasticsearch/data
path.logs: /usr/share/elasticsearch/logs
```

### Kibana Configuration

**`configs/kibana.yml`**
```yaml
server.host: "0.0.0.0"
server.port: 5601
server.name: "elk-kibana"

# Point to Elasticsearch
elasticsearch.hosts: ["http://elasticsearch:9200"]

# Logging
logging.appenders.file.type: file
logging.appenders.file.fileName: /var/log/kibana/kibana.log
logging.appenders.file.layout.type: json
logging.root.appenders: [default, file]
```

### Logstash Configuration

**`configs/logstash.yml`**
```yaml
# Logstash 8.x — api.http.* keys replace the 7.x http.host / http.port
api.http.host: "0.0.0.0"
api.http.port: 9600

# Logging (set to info once stable; debug is noisy)
log.level: info

# Pipeline settings (also set per-pipeline in pipelines.yml, but useful as defaults)
pipeline.workers: 2
pipeline.batch.size: 125
pipeline.batch.delay: 50

# X-Pack monitoring (push metrics to Elasticsearch — disabled here, use Stack Monitoring in Kibana instead)
xpack.monitoring.enabled: false
```

### Pipelines Configuration

**`configs/pipelines.yml`**
```yaml
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

## Step 7 — Local Testing (Optional)

If testing locally before deploying to AWS:

```bash
# 1. Install Docker Desktop (Windows/Mac) or Docker (Linux)
# 2. Ensure Docker has sufficient resources:
#    - At least 4GB RAM allocated
#    - 10GB disk space

# 3. Run Docker Compose locally
cd /path/to/elk-stack-project
docker compose up -d

# 4. Test locally before AWS deployment
curl http://localhost:9200/_cluster/health?pretty
curl http://localhost:5601/  # Open in browser
```

---

## Troubleshooting Phase 1

### Issue: Elasticsearch Container Exits Immediately

**Error:** Container shows `Exited (1) few seconds ago`

**Solution:**
```bash
# Check Elasticsearch logs
docker logs elasticsearch | tail -50

# Common fix: Set vm.max_map_count
sudo sysctl -w vm.max_map_count=262144

# Make it permanent
sudo bash -c 'echo "vm.max_map_count=262144" >> /etc/sysctl.conf'
sudo sysctl -p

# If on Windows/Mac Docker Desktop:
# Open Docker Desktop settings → Resources → Memory → set to 4GB+ → Restart Docker
```

### Issue: Kibana Shows "Kibana Server is Not Ready Yet"

**Solution:**
```bash
# Wait for Elasticsearch to fully start
docker compose logs elasticsearch | grep -i "started"

# Kibana needs ~60 seconds after ES starts
sleep 60

# Then refresh browser at http://<EC2_IP>:5601
```

### Issue: Out of Memory Errors

**Solution:**
```bash
# Reduce JVM heap sizes in docker-compose.yml
# Change from:
# - ES_JAVA_OPTS=-Xms1g -Xmx1g
# To:
# - ES_JAVA_OPTS=-Xms512m -Xmx512m

docker compose down
docker compose up -d
```

### Issue: Port Already in Use

**Solution:**
```bash
# Find process using the port (e.g., 9200)
lsof -i :9200  # On Linux/Mac
netstat -ano | findstr :9200  # On Windows

# Kill the process or use different port in docker-compose.yml
```

### Issue: Cannot Connect to Kibana from Browser

**Solution:**
```bash
# 1. Verify Kibana container is running
docker compose ps | grep kibana
# Should show: kibana  docker.elastic.co/kibana/kibana:8.11.0  Up X minutes

# 2. Check AWS Security Group allows port 5601
# AWS Console → EC2 → Security Groups → elk-stack-sg
# Verify inbound rule: 5601 from 0.0.0.0/0

# 3. Test connectivity from EC2 instance
curl -I http://localhost:5601

# 4. If using DNS, verify it resolves
nslookup <your-domain>
```

---

## Step 8 — Important Security Notes (For AWS)

### Before Production Deployment:

1. **Restrict Security Groups:**
   ```hcl
   # Instead of 0.0.0.0/0, use your IP or office IP range
   cidr_blocks = ["YOUR_IP/32"]
   ```

2. **Enable Elasticsearch Authentication:**
   - Phase 5 covers this in detail
   - Set `xpack.security.enabled: true`
   - Configure users and roles

3. **Use Private Subnets:**
   - Don't expose Elasticsearch directly to internet
   - Route through Nginx reverse proxy with authentication

4. **Enable TLS/SSL:**
   - Certificates for all inter-node communication
   - HTTPS for Kibana

5. **Set Up Backups:**
   - Configure Elasticsearch snapshots to S3
   - Regular backup schedule

---

## Step 9 — Cost Optimization

### AWS Pricing Considerations:

| Resource | Cost Impact | Optimization |
|----------|------------|--------------|
| t3.medium | ~$35/month | Min requirement; consider smaller for dev |
| 30GB storage | ~$3/month | Adjust based on log volume |
| Data transfer | ~$0.09/GB out | Keep in-region |
| Snapshots to S3 | ~$0.023/GB | Enable backup but monitor size |

### Tips:
- Stop instances when not in use (`terraform destroy`)
- Use spot instances for dev (`instance_type = "t3.medium.spot"`)
- Implement index lifecycle management (Phase 5)
- Archive old indices to S3 Glacier

---

## ✅ Phase 1 Completion Checklist

- [ ] AWS account created and credentials configured locally
- [ ] EC2 key pair created and downloaded
- [ ] Terraform successfully provisions EC2 instance
- [ ] EC2 instance security group allows inbound on 22, 5601, 9200, 5044
- [ ] Docker and Docker Compose installed on EC2
- [ ] `vm.max_map_count=262144` set on EC2
- [ ] All 5 containers (Elasticsearch, Logstash, Kibana, Filebeat, ElastAlert) show `Up` in `docker compose ps`
- [ ] `curl localhost:9200/_cluster/health` returns green or yellow status
- [ ] Kibana loads in browser at `http://<EC2_IP>:5601` without errors
- [ ] Kibana shows "Welcome to Elastic" or "Create your index pattern" page
- [ ] No error logs in Elasticsearch container (`docker logs elasticsearch`)
- [ ] SSH connectivity works with EC2 instance

---

## 🧠 Concepts You Learned in Phase 1

### ELK Stack Components

**Elasticsearch**
- Distributed search and analytics engine
- Stores logs as JSON documents in *indices*
- Provides full-text search with scoring and aggregations
- Horizontally scalable — add nodes to increase capacity

**Logstash**
- Data processing pipeline: Input → Filter → Output
- Receives logs from multiple sources (Filebeat, syslog, HTTP, etc.)
- Transforms/enriches logs (Grok parsing, GeoIP lookup, etc.)
- Outputs to Elasticsearch, S3, or other destinations

**Kibana**
- Web UI for querying and visualizing Elasticsearch data
- Discover: ad-hoc searching and field exploration
- Visualize: charts, maps, metrics
- Dashboards: combine multiple visualizations
- Alerts: trigger on specific conditions

**Filebeat**
- Lightweight log shipper agent — resource-efficient
- Tails log files and sends lines to Logstash (or directly to ES)
- Ensures delivery: keeps state to avoid duplicates
- Easily deployed across servers

### Docker Compose Multi-Service Orchestration

- **Services:** Each container is a named service (elasticsearch, logstash, kibana, filebeat)
- **Networking:** Containers communicate via service name (e.g., `elasticsearch:9200`)
- **Health checks:** Wait for dependencies (Kibana waits for Elasticsearch)
- **Volumes:** Persist data (es-data) across container restarts
- **Resource limits:** Control CPU/memory per container

### Key Infrastructure Concepts

- **vm.max_map_count:** OS-level setting for Elasticsearch memory management
- **Memory allocation:** JVM heap (`-Xms`, `-Xmx`) vs. container memory limits
- **Port mapping:** `"9200:9200"` maps container port 9200 to host port 9200
- **Health checks:** Determine when containers are ready (`service_healthy`)
- **Single-node cluster:** `discovery.type=single-node` for dev/test (production uses multi-node)

---

## ➡️ Next Step

Proceed to **[Phase 2 — Log Ingestion Pipelines](../phase-2-log-ingestion/Phase%202%20—%20Log%20Ingestion%20Pipelines.md)**
