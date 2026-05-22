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
http.host: "0.0.0.0"
http.port: 9600

# Pipeline settings
pipeline.workers: 2
pipeline.batch.size: 125
pipeline.batch.delay: 50

# X-Pack monitoring (reports to ES)
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

  logstash:
    image: docker.elastic.co/logstash/logstash:8.11.0
    container_name: logstash
    volumes:
      - ./configs/logstash.yml:/usr/share/logstash/config/logstash.yml:ro
      - ./configs/pipelines.yml:/usr/share/logstash/config/pipelines.yml:ro
      - ./phase-2-log-ingestion/logstash/pipelines:/usr/share/logstash/pipeline:ro
    ports:
      - "5044:5044"    # Beats input
      - "5000:5000"    # TCP input
      - "9600:9600"    # Logstash monitoring API
    networks:
      - elk-net
    depends_on:
      elasticsearch:
        condition: service_healthy
    environment:
      - LS_JAVA_OPTS=-Xms512m -Xmx512m

  kibana:
    image: docker.elastic.co/kibana/kibana:8.11.0
    container_name: kibana
    volumes:
      - ./configs/kibana.yml:/usr/share/kibana/config/kibana.yml:ro
    ports:
      - "5601:5601"
    networks:
      - elk-net
    depends_on:
      elasticsearch:
        condition: service_healthy

  filebeat:
    image: docker.elastic.co/beats/filebeat:8.11.0
    container_name: filebeat
    user: root
    volumes:
      - ./phase-2-log-ingestion/filebeat/filebeat.yml:/usr/share/filebeat/filebeat.yml:ro
      - /var/log:/var/log:ro              # System logs
      - /var/lib/docker/containers:/var/lib/docker/containers:ro  # Docker logs
      - filebeat-data:/usr/share/filebeat/data
    networks:
      - elk-net
    depends_on:
      - logstash
    command: filebeat -e -strict.perms=false

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

## 🐛 Common Issues

| Problem | Fix |
|---------|-----|
| Elasticsearch exits immediately | Run `sudo sysctl -w vm.max_map_count=262144` |
| Out of memory | Use `t3.medium` or larger; reduce `ES_JAVA_OPTS` heap to `-Xms512m -Xmx512m` |
| Port 5601 unreachable | Check Security Group inbound rules in AWS Console |
| Kibana shows "Kibana server is not ready yet" | ES is still starting; wait 60s and refresh |

---

## 🧠 Concepts You Learned in Phase 1

- **Elasticsearch** is a distributed search and analytics engine. It stores logs as JSON documents in *indices*.
- **Logstash** is a data processing pipeline — receives, transforms, and forwards logs.
- **Kibana** is the UI layer — query, visualize, and alert on data in Elasticsearch.
- **Filebeat** is a lightweight log shipper agent — tails log files and sends to Logstash or ES.
- `vm.max_map_count=262144` is an OS-level requirement for Elasticsearch to manage memory-mapped files.
- `discovery.type=single-node` tells ES not to look for cluster peers (fine for dev/single-node setups).

---

## ➡️ Next Step

Proceed to **[Phase 2 — Log Ingestion Pipelines](../phase-2-log-ingestion/README.md)**
