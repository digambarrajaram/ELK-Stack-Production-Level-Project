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
│  Elasticsearch  :9200 (TLS enabled)  │
│  Kibana         :5601 (TLS enabled)  │
│  Logstash       :5044 / 9600         │
│  Filebeat       (agent, no port)    │
│  ElastAlert2    (alert engine)      │
└─────────────────────────────────────┘
```

---

## Step 1 — Provision EC2 with Terraform

### 1.1 Create the Terraform files

**`terraform/provider.tf`**
```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.46.0"
    }
  }
}
provider "aws" {
  region = var.aws_region
}
```

**`terraform/main.tf`**
```hcl
# Fetch an Ubuntu 22.04 LTS Machine Image automatically
data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"] # Canonical
}

resource "aws_instance" "elk_instance" {
    ami = data.aws_ami.ubuntu.id
    instance_type = var.instance_type
    key_name = var.key_name

    # IMDSv2 enforced (security best practice — required by AWS Security Hub)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"   # enforces IMDSv2
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    encrypted             = true   # EBS encryption at rest
    delete_on_termination = true
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
      Name = var.instance_name
      Project = var.project
    }
}

resource "aws_security_group" "elk_sg" {
    name = "elk-stack-sg"
    description = "Security group for elk stack"

    tags = {
      Name = "elk-stack-sg"
      Project = var.project
    }
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.elk_sg.id
  cidr_ipv4 = var.internet_route
  ip_protocol = "tcp"
  from_port = 22
  to_port = 22
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  security_group_id = aws_security_group.elk_sg.id
  cidr_ipv4 = var.internet_route
  ip_protocol = "tcp"
  from_port = 443
  to_port = 443
}
resource "aws_vpc_security_group_ingress_rule" "logstash" {
  security_group_id = aws_security_group.elk_sg.id
  cidr_ipv4 = var.internet_route
  ip_protocol = "tcp"
  from_port = 5044
  to_port = 5044
}
resource "aws_vpc_security_group_ingress_rule" "kibana" {
  security_group_id = aws_security_group.elk_sg.id
  cidr_ipv4 = var.internet_route
  ip_protocol = "tcp"
  from_port = 5601
  to_port = 5601
}

resource "aws_vpc_security_group_ingress_rule" "web_API_port_Elastic_Logstash" {
  security_group_id = aws_security_group.elk_sg.id
  cidr_ipv4 = var.internet_route
  ip_protocol = "tcp"
  from_port = 9600
  to_port = 9600
}

resource "aws_vpc_security_group_ingress_rule" "ElasticSearch" {
  security_group_id = aws_security_group.elk_sg.id
  cidr_ipv4 = var.internet_route
  ip_protocol = "tcp"
  from_port = 9200
  to_port = 9200
}
resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.elk_sg.id
  cidr_ipv4 = var.internet_route
  ip_protocol = "tcp"
  from_port = 80
  to_port = 80
}

resource "aws_vpc_security_group_egress_rule" "allow_all_outbound" {
  security_group_id = aws_security_group.elk_sg.id
  cidr_ipv4         = var.internet_route
  ip_protocol       = "-1" # Semantically represents all protocols
}
```

**`terraform/variables.tf`**
```hcl
variable "instance_type" {
  type        = string
  default     = "t3.medium"
  description = "EC2 instance type"
}

variable "key_name" {
  type        = string
  default     = "elk-stack-server_keypair"
  description = "EC2 key pair"
}

variable "instance_name" {
  type        = string
  default     = "elk-instance"
  description = "EC2 instance name"
}

variable "aws_region" {
  type        = string
  default     = "ap-south-1"
  description = "AWS Region"
}

variable "project" {
  type        = string
  default     = "elk-stack"
  description = "Project name"
}

variable "internet_route" {
  default     = "0.0.0.0/0"
  description = "Internet route"
}

```

**`terraform/outputs.tf`**
```hcl
output "instance_id" {
  value = aws_instance.elk_instance.id
}
output "public_ip" {
  value = aws_instance.elk_instance.public_ip
}
output "private_ip" {
  value = aws_instance.elk_instance.private_ip
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

network.host: 0.0.0.0
http.port: 9200

# discovery.type must NOT be set to single-node in ES 9.x
# (the setting was removed; single-node behaviour is auto-detected)
# For ES 8.x only, you may keep: discovery.type: single-node

# ── Security (enabled by default in 8.x/9.x — config only) ────────────────
xpack.security.enabled: true                  # explicit but redundant on 8+/9+
xpack.security.enrollment.enabled: false      # true only if using Kibana token enrollment

# TLS for HTTP layer (REST API)
xpack.security.http.ssl.enabled: true
xpack.security.http.ssl.keystore.path: certs/elastic-certificates.p12
xpack.security.http.ssl.truststore.path: certs/elastic-certificates.p12

# TLS for transport layer (node-to-node communication).
xpack.security.transport.ssl.enabled: true
xpack.security.transport.ssl.verification_mode: certificate
xpack.security.transport.ssl.keystore.path: certs/elastic-certificates.p12
xpack.security.transport.ssl.truststore.path: certs/elastic-certificates.p12

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
    env_file: .env
    environment:
      - discovery.type=single-node
      - ES_JAVA_OPTS=-Xms1g -Xmx1g
      - xpack.security.enabled=true
      - xpack.security.enrollment.enabled=false
      - ELASTIC_PASSWORD=${ELASTIC_PASSWORD}
    ulimits:
      memlock:
        soft: -1
        hard: -1
    volumes:
      - es-data:/usr/share/elasticsearch/data
      - ./configs/elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml:ro
      - ./security/certs:/usr/share/elasticsearch/config/certs
    ports:
      - "9200:9200"
      - "9300:9300"
    networks:
      - elk-net
    healthcheck:
      # -u reads ELASTIC_PASSWORD from the container env (injected above)
      test: ["CMD-SHELL", "curl -sk -u elastic:${ELASTIC_PASSWORD} https://localhost:9200/_cluster/health | grep -q 'status'"]
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
    env_file: .env                          # gives pipeline.conf access to ${LOGSTASH_SYSTEM_PASSWORD} etc.
    environment:
      - LS_JAVA_OPTS=-Xms1g -Xmx1g
    volumes:
      - ./configs/logstash.yml:/usr/share/logstash/config/logstash.yml:ro
      - ./configs/pipelines.yml:/usr/share/logstash/config/pipelines.yml:ro
      - ./phase-2-log-ingestion/logstash/pipelines:/usr/share/logstash/pipeline:ro
      - ./security/certs:/usr/share/logstash/config/certs:ro
    ports:
      - "5044:5044"
      - "5000:5000"
      - "9600:9600"
    networks:
      - elk-net
    depends_on:
      elasticsearch:
        condition: service_healthy
    deploy:
      resources:
        limits:
          memory: 1500m

  kibana:
    image: docker.elastic.co/kibana/kibana:8.11.0
    container_name: kibana
    user: root
    command: kibana --allow-root
    env_file: .env
    environment:
      - NODE_OPTIONS=--max-old-space-size=512
      # These ELASTICSEARCH_* vars are natively recognised by Kibana 8.x
      # and override anything set in kibana.yml — no yml password needed
      - ELASTICSEARCH_HOSTS=https://elasticsearch:9200
      - ELASTICSEARCH_USERNAME=kibana_system
      - ELASTICSEARCH_PASSWORD=${KIBANA_SYSTEM_PASSWORD}
      - ELASTICSEARCH_SSL_CERTIFICATEAUTHORITIES=/usr/share/kibana/config/certs/elastic-stack-ca.p12
      - ELASTICSEARCH_SSL_VERIFICATIONMODE=certificate
    volumes:
      - ./configs/kibana.yml:/usr/share/kibana/config/kibana.yml:ro
      - ./security/certs:/usr/share/kibana/config/certs:ro
    ports:
      - "5601:5601"
    networks:
      - elk-net
    depends_on:
      elasticsearch:
        condition: service_healthy
    deploy:
      resources:
        limits:
          memory: 800m

  filebeat:
    image: docker.elastic.co/beats/filebeat:8.11.0
    container_name: filebeat
    user: root
    env_file: .env
    volumes:
      - ./phase-2-log-ingestion/filebeat/filebeat.yml:/usr/share/filebeat/filebeat.yml:ro
      - /var/log:/var/log:ro
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - filebeat-data:/usr/share/filebeat/data
      - ./security/certs:/usr/share/filebeat/config/certs:ro
    networks:
      - elk-net
    depends_on:
      - logstash
    command: filebeat -e -strict.perms=false
    deploy:
      resources:
        limits:
          memory: 250m

  elastalert:
      image: jertel/elastalert2:latest
      container_name: elastalert2
      env_file: .env
      environment:
        - TZ=Asia/Kolkata
      volumes:
        - ./phase-4-alerting/elastalert2/config.yaml.tpl:/opt/elastalert/config.yaml.tpl:ro
        - ./phase-4-alerting/elastalert2/rules:/opt/elastalert/rules:ro
        - ./phase-4-alerting/elastalert2/data:/opt/elastalert/data
        - ./phase-4-alerting/elastalert2/smtp_auth.yaml:/opt/elastalert/smtp_auth.yaml:ro
      entrypoint:
        - sh
        - -c
        - |
          python3 -c "
          import os
          t = open('/opt/elastalert/config.yaml.tpl').read()
          for k, v in os.environ.items():
              t = t.replace('\$' + k, v)
          open('/tmp/config.yaml', 'w').write(t)
          "
          exec elastalert --config /tmp/config.yaml
      depends_on:
        elasticsearch:
          condition: service_healthy
      networks:
        - elk-net
      restart: unless-stopped

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
curl -sk -u elastic:${ELASTIC_PASSWORD} https://localhost:9200/_cluster/health?pretty
# Expected: "status" : "green" or "yellow"
```

**Open Kibana in browser:**
```
http://<EC2_PUBLIC_IP>:5601
```

---

## ✅ Phase 1 Checklist

- [ ] Terraform successfully provisions EC2 instance
- [ ] All 5 containers (ES, Logstash, Kibana, Filebeat, ElastAlert2) show `Up` in `docker compose ps`
- [ ] `curl -sk -u elastic:${ELASTIC_PASSWORD} https://localhost:9200/_cluster/health` returns green/yellow
- [ ] Kibana loads in the browser at `:5601`
- [ ] `docker compose logs elasticsearch` shows no errors

---

## Step 6 — Phase 1 vs Phase 2: Understanding the Architecture Progression

### Phase 1: Infrastructure Only
In Phase 1, we:
- ✅ Provision EC2 instance with Terraform
- ✅ Install Docker and Docker Compose
- ✅ Start all containers: Elasticsearch, Logstash, Kibana, Filebeat, ElastAlert2
- ✅ Configure security with TLS encryption and authentication
- ✅ Verify all services are running and healthy

**What we DON'T do in Phase 1:**
- ❌ Create custom Kibana dashboards and visualizations
- ❌ Configure advanced alerting rules (beyond basic ElastAlert2 setup)
- ❌ Implement index lifecycle management policies
- ❌ Configure advanced security features like RBAC roles and SAML

### Phase 2: Log Ingestion Pipelines
In Phase 2, we:
- ✅ Configure Filebeat to watch log files for nginx, application, and syslog
- ✅ Write Logstash pipelines with Grok filters for log parsing and enrichment
- ✅ Create combined.conf pipeline with geoIP and user-agent processing
- ✅ Start ingesting and parsing real logs from simulated sources

**Phase 2 Update to docker-compose.yml:**
*(No changes needed - Filebeat and Logstash pipelines are already configured in Phase 1)*
```diff
   logstash:
     volumes:
       - ./configs/logstash.yml:/usr/share/logstash/config/logstash.yml:ro
       - ./configs/pipelines.yml:/usr/share/logstash/config/pipelines.yml:ro
       - ./phase-2-log-ingestion/logstash/pipelines:/usr/share/logstash/pipeline:ro
```
When you're ready for Phase 2, you'll focus on creating test log data and verifying the parsing works correctly.
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

network.host: 0.0.0.0
http.port: 9200

# discovery.type must NOT be set to single-node in ES 9.x
# (the setting was removed; single-node behaviour is auto-detected)
# For ES 8.x only, you may keep: discovery.type: single-node

# ── Security (enabled by default in 8.x/9.x — config only) ────────────────
xpack.security.enabled: true                  # explicit but redundant on 8+/9+
xpack.security.enrollment.enabled: false      # true only if using Kibana token enrollment

# TLS for HTTP layer (REST API)
xpack.security.http.ssl.enabled: true
xpack.security.http.ssl.keystore.path: certs/elastic-certificates.p12
xpack.security.http.ssl.truststore.path: certs/elastic-certificates.p12

# TLS for transport layer (node-to-node communication).
xpack.security.transport.ssl.enabled: true
xpack.security.transport.ssl.verification_mode: certificate
xpack.security.transport.ssl.keystore.path: certs/elastic-certificates.p12
xpack.security.transport.ssl.truststore.path: certs/elastic-certificates.p12

path.data: /usr/share/elasticsearch/data
path.logs: /usr/share/elasticsearch/logs
```

### Kibana Configuration

**`configs/kibana.yml`**
```yaml
server.host: "0.0.0.0"
server.port: 5601
server.name: "elk-kibana"

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
curl -sk -u elastic:${ELASTIC_PASSWORD} https://localhost:9200/_cluster/health?pretty
curl -sk https://localhost:5601/  # Open in browser
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

# Then refresh browser at https://<EC2_IP>:5601
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
curl -I -sk -u elastic:${ELASTIC_PASSWORD} https://localhost:5601

# 4. If using DNS, verify it resolves
nslookup <your-domain>
```

---

## Step 8 — Important Security Notes (For AWS)

The basic security (TLS encryption and authentication) is already configured in Phase 1. For production deployment, consider these additional hardening steps:

### Before Production Deployment:

1. **Restrict Security Groups:**
    ```hcl
    # Instead of 0.0.0.0/0, use your IP or office IP range
    cidr_blocks = ["YOUR_IP/32"]
    ```

2. **Configure Advanced Security Features (Phase 5):**
    - Set up Role-Based Access Control (RBAC) with custom roles
    - Implement SAML or LDAP authentication for enterprise integration
    - Configure audit logging for compliance

3. **Use Private Subnets:**
    - Don't expose Elasticsearch directly to internet
    - Route through Nginx reverse proxy with authentication
    - Consider using AWS PrivateLink for secure access

4. **Enable Encryption at Rest:**
    - Configure EBS volume encryption for EC2 instance
    - Consider encrypted snapshots for backup data

5. **Set Up Backups:**
    - Configure Elasticsearch snapshots to S3
    - Regular backup schedule with retention policies

6. **Monitoring and Logging:**
    - Enable X-Pack monitoring
    - Set up logging for all ELK components
    - Implement alerting for security events

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
- [ ] All 5 containers (Elasticsearch, Logstash, Kibana, Filebeat, ElastAlert2) show `Up` in `docker compose ps`
- [ ] `curl -sk -u elastic:${ELASTIC_PASSWORD} https://localhost:9200/_cluster/health` returns green or yellow status
- [ ] Kibana loads in browser at `https://<EC2_IP>:5601` without errors
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
