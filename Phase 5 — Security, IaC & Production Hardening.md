# Phase 5 — Security, IaC & Production Hardening

**Goal:** Harden the ELK stack with TLS encryption, RBAC, Index Lifecycle Management (ILM), and finalize the Terraform IaC for a fully reproducible production deployment.

**Time estimate:** 4–5 hours

**What you'll learn:** Elasticsearch built-in security, TLS certificate generation, RBAC, ILM policies, Terraform modules, production readiness

---

## 📐 What We're Hardening

```
Before Phase 5 (insecure):                After Phase 5 (hardened):
─────────────────────────                 ────────────────────────────
Elasticsearch: no TLS/auth  ──►           Elasticsearch: TLS + RBAC
Kibana: no auth             ──►           Kibana: SSO via ES native realm
Logstash → ES: plaintext    ──►           Logstash → ES: TLS + API key
No data retention policy    ──►           ILM: hot→warm→cold→delete cycle
Manual EC2 setup            ──►           Full Terraform IaC
```

---

## Step 1 — Generate TLS Certificates with Subject Alternative Names (SANs)

Elasticsearch ships with `elasticsearch-certutil` to generate self-signed certs. **Important:** Certificates must include SANs (Subject Alternative Names) for hostname verification to work.

### 1.1 Start Elasticsearch (if not already running)

```bash
docker compose up -d elasticsearch
# Wait ~30 seconds for the container to be ready
```

### 1.2 Generate CA Certificate

```bash
docker exec -it elasticsearch elasticsearch-certutil ca \
  --out /tmp/elastic-stack-ca.p12 --pass ""
```

### 1.3 Generate Node Certificate with SANs

**Critical:** Include DNS names and IPs for your deployment. Adjust IPs based on your Docker network.

```bash
docker exec -it elasticsearch elasticsearch-certutil cert \
  --ca /tmp/elastic-stack-ca.p12 --ca-pass "" \
  --dns localhost --dns elasticsearch \
  --ip 127.0.0.1 --ip 172.18.0.2 \
  --out /tmp/elastic-certificates.p12 --pass ""
```

> **Why SANs matter:** Without them, hostname verification fails with "No subject alternative names present" error when tools like elasticsearch-reset-password try to connect.

### 1.4 Copy Certificates to Your Host

```bash
docker cp elasticsearch:/tmp/elastic-stack-ca.p12 ./security/certs/elastic-stack-ca.p12
docker cp elasticsearch:/tmp/elastic-certificates.p12 ./security/certs/elastic-certificates.p12
```

### 1.5 Fix Ownership for Elasticsearch Container User (UID 1000)

```bash
sudo chown 1000:0 ./security/certs/elastic-stack-ca.p12 ./security/certs/elastic-certificates.p12
sudo chmod 640 ./security/certs/elastic-stack-ca.p12 ./security/certs/elastic-certificates.p12
```

### 1.6 Extract PEM Files for Other Tools

ElastAlert and some clients need PEM format (not PKCS12):

```bash
# Extract CA certificate to PEM (no password since we generated with --pass "")
openssl pkcs12 -in ./security/certs/elastic-stack-ca.p12 \
  -nokeys -passin pass:"" \
  | openssl x509 -out ./security/certs/elastic-stack-ca.pem

# Verify it looks correct
head -2 ./security/certs/elastic-stack-ca.pem
# Should show: -----BEGIN CERTIFICATE-----
```

### 1.7 Restart Elasticsearch and Verify TLS is Working

```bash
docker compose down && docker compose up -d elasticsearch
sleep 30

# Should show TLS handshake (no certificate errors)
curl -vk https://localhost:9200 2>&1 | head -20
```

---

---

## Step 2 — Configure Docker Compose with TLS, Security & Healthcheck

Security (authentication + transport TLS) is **on by default in ES 8.x/9.x**. This step configures the HTTP TLS layer and ensures all services are properly wired.

### 2.1 Update `docker-compose.yml`

**Critical:** Ensure `xpack.security.enabled=true` in the environment variables (not `false`), and all services mount the certs directory.

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
      - ./security/certs:/usr/share/elasticsearch/config/certs:ro
    ports:
      - "9200:9200"
      - "9300:9300"
    networks:
      - elk-net
    healthcheck:
      test: ["CMD-SHELL", "curl -sk -u elastic:${ELASTIC_PASSWORD} https://localhost:9200/_cluster/health | grep -q 'status'"]
      interval: 30s
      timeout: 10s
      retries: 5
    deploy:
      resources:
        limits:
          memory: 2g

  kibana:
    image: docker.elastic.co/kibana/kibana:8.11.0
    container_name: kibana
    user: root
    command: kibana --allow-root
    env_file: .env
    environment:
      - ELASTICSEARCH_HOSTS=https://elasticsearch:9200
      - ELASTICSEARCH_USERNAME=kibana_system
      - ELASTICSEARCH_PASSWORD=${KIBANA_SYSTEM_PASSWORD}
      - ELASTICSEARCH_SSL_CERTIFICATEAUTHORITIES=/usr/share/kibana/config/certs/elastic-stack-ca.p12
      - ELASTICSEARCH_SSL_VERIFICATIONMODE=certificate
      - NODE_OPTIONS=--max-old-space-size=512
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

  logstash:
    image: docker.elastic.co/logstash/logstash:8.11.0
    container_name: logstash
    env_file: .env
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
    environment:
      - LS_JAVA_OPTS=-Xms1g -Xmx1g
    deploy:
      resources:
        limits:
          memory: 1500m

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
      - ./security/certs:/opt/elastalert/certs:ro
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

### 2.2 Update `.env` with Real Passwords

```bash
# .env — DO NOT commit this file, add to .gitignore

ELASTIC_PASSWORD=<your_elastic_password_from_reset>
KIBANA_SYSTEM_PASSWORD=KibanaSystem123!
LOGSTASH_SYSTEM_PASSWORD=LogstashSystem123!

# ElastAlert SMTP
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=your_email@gmail.com
SMTP_PASS=your_gmail_app_password
ALERT_FROM=your_email@gmail.com
ALERT_TO=recipient@example.com
```

### 2.3 Update `configs/elasticsearch.yml`

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
xpack.security.enrollment.enabled: false

# TLS for HTTP layer (REST API)
xpack.security.http.ssl.enabled: true
xpack.security.http.ssl.keystore.path: certs/elastic-certificates.p12
xpack.security.http.ssl.truststore.path: certs/elastic-certificates.p12

# TLS for transport layer (node-to-node communication)
xpack.security.transport.ssl.enabled: true
xpack.security.transport.ssl.verification_mode: certificate
xpack.security.transport.ssl.keystore.path: certs/elastic-certificates.p12
xpack.security.transport.ssl.truststore.path: certs/elastic-certificates.p12

path.data: /usr/share/elasticsearch/data
path.logs: /usr/share/elasticsearch/logs
```

### 2.3 Update `configs/elasticsearch.yml`

[Elasticsearch config already shown in previous section - use the same]

### 2.4 Reset Built-in User Passwords

```bash
# Restart all containers to apply the config and .env
docker compose down && docker compose up -d elasticsearch
sleep 30

# Reset the elastic superuser password interactively
docker exec -it elasticsearch elasticsearch-reset-password -u elastic -i

# When prompted, type a secure password (you'll need it for .env)
# Copy the password and update .env with it

# Also reset kibana_system if not already done
docker exec -it elasticsearch elasticsearch-reset-password -u kibana_system -i

# And logstash_system
docker exec -it elasticsearch elasticsearch-reset-password -u logstash_system -i
```

> ⚠️ **Save these passwords securely:** Store them in `.env` (and add `.env` to `.gitignore`). Never commit passwords to Git.

### 2.5 Set Passwords for System Users via API

```bash
# Load passwords from .env
source .env

# Set kibana_system password
curl -sk -u elastic:${ELASTIC_PASSWORD} \
  -X POST "https://localhost:9200/_security/user/kibana_system/_password" \
  -H 'Content-Type: application/json' \
  -d "{\"password\":\"${KIBANA_SYSTEM_PASSWORD}\"}"

# Set logstash_system password
curl -sk -u elastic:${ELASTIC_PASSWORD} \
  -X POST "https://localhost:9200/_security/user/logstash_system/_password" \
  -H 'Content-Type: application/json' \
  -d "{\"password\":\"${LOGSTASH_SYSTEM_PASSWORD}\"}"
```

### 2.6 Verify HTTPS is Working

```bash
source .env

# Should return JSON cluster info (status 200)
curl -u elastic:${ELASTIC_PASSWORD} \
  --cacert ./security/certs/elastic-stack-ca.pem \
  https://localhost:9200

# Should return 401 Unauthorized (means auth is active)
curl http://localhost:9200

# Should also work without SSL verification (for testing)
curl -sk -u elastic:${ELASTIC_PASSWORD} https://localhost:9200
```

---

## Step 3 — RBAC: Roles and Users

Define least-privilege roles for different consumers via API.

### 3.1 Create Roles and Users

```bash
# Load environment variables
source .env

# Create the logstash_writer role
curl -X POST "https://localhost:9200/_security/role/logstash_writer" \
  -u elastic:${ELASTIC_PASSWORD} \
  -H 'Content-Type: application/json' \
  --cacert ./security/certs/elastic-stack-ca.pem \
  -d '{
    "cluster": ["manage_index_templates", "monitor", "manage_ilm"],
    "indices": [{
      "names": ["nginx-access-*", "app-logs-*", "syslog-*"],
      "privileges": ["write", "create", "create_index", "manage", "manage_ilm"]
    }]
  }'

# Create logstash internal user
curl -X POST "https://localhost:9200/_security/user/logstash_internal" \
  -u elastic:${ELASTIC_PASSWORD} \
  -H 'Content-Type: application/json' \
  --cacert ./security/certs/elastic-stack-ca.pem \
  -d '{
    "password": "logstash_secure_password",
    "roles": ["logstash_writer"],
    "full_name": "Logstash Internal User"
  }'

# Create dashboard viewer role and user
curl -X POST "https://localhost:9200/_security/role/viewer" \
  -u elastic:${ELASTIC_PASSWORD} \
  -H 'Content-Type: application/json' \
  --cacert ./security/certs/elastic-stack-ca.pem \
  -d '{
    "cluster": ["monitor"],
    "indices": [{
      "names": ["nginx-access-*", "app-logs-*", "syslog-*"],
      "privileges": ["read", "view_index_metadata"]
    }]
  }'

curl -X POST "https://localhost:9200/_security/user/dashboard_viewer" \
  -u elastic:${ELASTIC_PASSWORD} \
  -H 'Content-Type: application/json' \
  --cacert ./security/certs/elastic-stack-ca.pem \
  -d '{
    "password": "viewer_secure_password",
    "roles": ["viewer"],
    "full_name": "Dashboard Viewer"
  }'

# Create Elasticsearch API key for Logstash (preferred method — rotatable, auditable)
curl -X POST "https://localhost:9200/_security/api_key" \
  -u elastic:${ELASTIC_PASSWORD} \
  -H 'Content-Type: application/json' \
  --cacert ./security/certs/elastic-stack-ca.pem \
  -d '{
    "name": "logstash-api-key",
    "role_descriptors": {
      "logstash_writer": {
        "cluster": ["manage_index_templates", "monitor"],
        "indices": [{
          "names": ["nginx-access-*", "app-logs-*", "syslog-*"],
          "privileges": ["write", "create", "create_index"]
        }]
      }
    }
  }'
```

> **API Key Response:** Save the `id` and `api_key` from the response — they're shown only once and needed for Logstash configuration.

### 3.2 Verify Roles and Users

```bash
# List all custom roles
curl -s https://localhost:9200/_security/role/ \
  -u elastic:${ELASTIC_PASSWORD} \
  --cacert ./security/certs/elastic-stack-ca.pem | jq .

# List all users
curl -s https://localhost:9200/_security/user/ \
  -u elastic:${ELASTIC_PASSWORD} \
  --cacert ./security/certs/elastic-stack-ca.pem | jq .
```

---

## Step 4 — Index Lifecycle Management (ILM)

ILM automates the index lifecycle: **hot → warm → cold → delete**, reducing storage costs and ensuring timely data cleanup.

### 4.1 Create ILM Policy

First, create the policy file (JSON does NOT support comments):

```bash
cat > ilm/policy.json << 'EOF'
{
  "policy": {
    "phases": {
      "hot": {
        "min_age": "0ms",
        "actions": {
          "rollover": {
            "max_primary_shard_size": "5gb",
            "max_age": "1d"
          },
          "set_priority": {
            "priority": 100
          }
        }
      },
      "warm": {
        "min_age": "7d",
        "actions": {
          "shrink": {
            "number_of_shards": 1
          },
          "forcemerge": {
            "max_num_segments": 1
          },
          "set_priority": {
            "priority": 50
          },
          "readonly": {}
        }
      },
      "cold": {
        "min_age": "30d",
        "actions": {
          "set_priority": {
            "priority": 0
          },
          "readonly": {}
        }
      },
      "delete": {
        "min_age": "90d",
        "actions": {
          "delete": {
            "delete_searchable_snapshot": true
          }
        }
      }
    }
  }
}
EOF
```

Now apply it to Elasticsearch:

```bash
source .env

# Create the ILM policy
curl -X PUT "https://localhost:9200/_ilm/policy/elk-logs-policy" \
  -u elastic:${ELASTIC_PASSWORD} \
  -H 'Content-Type: application/json' \
  --cacert ./security/certs/elastic-stack-ca.pem \
  -d @ilm/policy.json

# Expected response: {"acknowledged":true}
```

### 4.2 Create Composable Index Template

> **Important:** Always use `/_index_template/` (new composable API), NOT `/_template/` (legacy — removed in ES 9.0).

> **Gotcha:** If you get an "illegal_argument_exception" about template priority conflicts, it means an old template exists. Delete it first using the command in 4.3.

```bash
# Apply the index template with priority 1 to ensure ILM is applied
curl -X PUT "https://localhost:9200/_index_template/elk-logs-template" \
  -u elastic:${ELASTIC_PASSWORD} \
  -H 'Content-Type: application/json' \
  --cacert ./security/certs/elastic-stack-ca.pem \
  -d '{
    "index_patterns": ["nginx-access-*", "app-logs-*", "syslog-*"],
    "priority": 1,
    "template": {
      "settings": {
        "number_of_shards": 1,
        "number_of_replicas": 0,
        "index.lifecycle.name": "elk-logs-policy",
        "index.lifecycle.rollover_alias": "logs"
      }
    }
  }'

# Expected response: {"acknowledged":true}
```

### 4.3 Fix Template Conflicts (if needed)

If you get a priority conflict error, check and delete the old template:

```bash
# See what templates exist
curl -s https://localhost:9200/_index_template?pretty \
  -u elastic:${ELASTIC_PASSWORD} \
  --cacert ./security/certs/elastic-stack-ca.pem | jq '.index_templates[] | .name'

# Delete the conflicting old template (e.g., nginx-access-template)
curl -X DELETE "https://localhost:9200/_index_template/nginx-access-template" \
  -u elastic:${ELASTIC_PASSWORD} \
  --cacert ./security/certs/elastic-stack-ca.pem

# Then retry step 4.2
```

### 4.4 Verify ILM Policy

```bash
# Get the full policy
curl -s https://localhost:9200/_ilm/policy/elk-logs-policy?pretty \
  -u elastic:${ELASTIC_PASSWORD} \
  --cacert ./security/certs/elastic-stack-ca.pem

# Check ILM status for indices (will show empty until indices are created)
curl -s https://localhost:9200/nginx-access-*/_ilm/explain?pretty \
  -u elastic:${ELASTIC_PASSWORD} \
  --cacert ./security/certs/elastic-stack-ca.pem
```

---

## Step 5 — Configure Kibana, Logstash, and ElastAlert for TLS

### 5.1 Kibana Configuration

Kibana retrieves Elasticsearch connection settings from environment variables (set in docker-compose.yml). The `configs/kibana.yml` should be minimal:

```yaml
server.host: "0.0.0.0"
server.port: 5601
server.name: "elk-kibana"

logging.appenders.file.type: file
logging.appenders.file.fileName: /var/log/kibana/kibana.log
logging.appenders.file.layout.type: json
logging.root.appenders: [default, file]
```

All Elasticsearch connection settings come from docker-compose.yml environment variables (already configured in Step 2.1):

```yaml
ELASTICSEARCH_HOSTS=https://elasticsearch:9200
ELASTICSEARCH_USERNAME=kibana_system
ELASTICSEARCH_PASSWORD=${KIBANA_SYSTEM_PASSWORD}
ELASTICSEARCH_SSL_CERTIFICATEAUTHORITIES=/usr/share/kibana/config/certs/elastic-stack-ca.p12
ELASTICSEARCH_SSL_VERIFICATIONMODE=certificate
```

Verify Kibana is healthy:

```bash
docker compose logs kibana --tail=30
# Should show messages like "Kibana is ready" with no SSL errors
```

### 5.2 Logstash Configuration

Update `configs/logstash.yml`:

```yaml
api.http.host: "0.0.0.0"
api.http.port: 9600
log.level: info
pipeline.workers: 2
pipeline.batch.size: 125
pipeline.batch.delay: 50
xpack.monitoring.enabled: false
```

Update your pipeline files in `phase-2-log-ingestion/logstash/pipelines/combined.conf` to use TLS and authentication:

```ruby
output {
  elasticsearch {
    hosts => ["https://elasticsearch:9200"]
    index => "app-logs-%{+YYYY.MM.dd}"
    
    # Use TLS
    ssl => true
    cacert => "/usr/share/logstash/config/certs/elastic-stack-ca.pem"
    
    # Authenticate with Logstash user
    user => "logstash_system"
    password => "${LOGSTASH_SYSTEM_PASSWORD}"
  }
}
```

Verify Logstash connects successfully:

```bash
docker compose logs logstash --tail=30
# Should show "Logstash is ready" with no auth or SSL errors
```

### 5.3 ElastAlert2 Configuration

Create `phase-4-alerting/elastalert2/config.yaml.tpl` as a template (note `.tpl` extension):

```yaml
es_host: elasticsearch
es_port: 9200
es_username: elastic
es_password: $ELASTIC_PASSWORD

use_ssl: true
verify_certs: false

writeback_index: elastalert_status
writeback_alias: elastalert
run_every:
  minutes: 1
buffer_time:
  minutes: 15
alert_time_limit:
  days: 2
use_local_time: true
timezone: Asia/Kolkata
rules_folder: /opt/elastalert/rules
logging_level: INFO

smtp_host: $SMTP_HOST
smtp_port: $SMTP_PORT
smtp_auth_file: /opt/elastalert/smtp_auth.yaml
from_addr: $ALERT_FROM
email_reply_to: $ALERT_FROM
smtp_starttls: true
smtp_ssl: false
```

The docker-compose.yml already has Python-based environment variable substitution in the entrypoint (Step 2.1), so variables like `$ELASTIC_PASSWORD` are automatically replaced at startup.

Verify ElastAlert is connecting:

```bash
docker compose logs elastalert2 --tail=30
# Should show "Elastalert is ready" with no connection errors
```

---

## Step 6 — Final Terraform (Full IaC)

Complete production Terraform with remote state, proper networking, and security hardening.


### `terraform/main.tf`

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"   # Updated from 5.x — latest as of 2025/2026
    }
  }

  # Remote state — prevents concurrent modifications
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "elk-stack/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

# VPC for network isolation
resource "aws_vpc" "elk_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "elk-vpc", Project = "elk-stack" }
}

resource "aws_subnet" "elk_public_subnet" {
  vpc_id                  = aws_vpc.elk_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = { Name = "elk-public-subnet" }
}

resource "aws_internet_gateway" "elk_igw" {
  vpc_id = aws_vpc.elk_vpc.id
  tags   = { Name = "elk-igw" }
}

resource "aws_route_table" "elk_rt" {
  vpc_id = aws_vpc.elk_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.elk_igw.id
  }
}

resource "aws_route_table_association" "elk_rta" {
  subnet_id      = aws_subnet.elk_public_subnet.id
  route_table_id = aws_route_table.elk_rt.id
}

# Security group — restrict SSH to your IP only
resource "aws_security_group" "elk_sg" {
  name   = "elk-stack-sg"
  vpc_id = aws_vpc.elk_vpc.id

  ingress {
    description = "SSH from my IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]  # Your IP only — e.g. "1.2.3.4/32"
  }

  ingress {
    description = "Kibana HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  ingress {
    description = "Kibana HTTP (redirect to HTTPS)"
    from_port   = 5601
    to_port     = 5601
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "elk-sg", Project = "elk-stack" }
}

# IAM role for EC2 (for CloudWatch agent, SSM access)
resource "aws_iam_role" "elk_ec2_role" {
  name = "elk-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.elk_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "elk_profile" {
  name = "elk-instance-profile"
  role = aws_iam_role.elk_ec2_role.name
}

# EC2 Instance
resource "aws_instance" "elk_server" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = aws_subnet.elk_public_subnet.id
  vpc_security_group_ids = [aws_security_group.elk_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.elk_profile.name

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

  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    project_repo = var.project_repo
  }))

  tags = {
    Name        = "elk-stack-server"
    Project     = "elk-stack"
    Environment = "production"
  }
}
```

### `terraform/variables.tf`

```hcl
variable "aws_region"    { default = "us-east-1" }
variable "instance_type" { default = "t3.medium" }
variable "key_name"      { type = string }
variable "my_ip_cidr"    {
  type        = string
  description = "Your IP in CIDR notation — e.g. 1.2.3.4/32"
}
variable "ami_id" {
  default     = "ami-0c02fb55956c7d316"  # Ubuntu 22.04 us-east-1 — verify latest before use
  description = "AMI ID — check AWS console for the latest Ubuntu 22.04/24.04 LTS in your region"
}
variable "project_repo"  { type = string; default = "" }
```

> ⚠️ **AMI note:** The AMI ID `ami-0c02fb55956c7d316` was valid for Ubuntu 22.04 LTS in `us-east-1` at time of writing. AMI IDs change with patch releases. Always verify the current ID via the [AWS console](https://console.aws.amazon.com/ec2/v2/home#Images) or with:
> ```bash
> aws ec2 describe-images \
>   --owners 099720109477 \
>   --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
>   --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
>   --output text
> ```

---

## Step 7 — Production Readiness Checklist

- [ ] **Certificates Generated**
  - [ ] CA cert (elastic-stack-ca.p12) generated with `--pass ""`
  - [ ] Node cert (elastic-certificates.p12) generated with SANs: `--dns localhost --dns elasticsearch --ip 127.0.0.1 --ip 172.18.0.2`
  - [ ] Certs owned by UID 1000 (Elasticsearch user) with 640 permissions
  - [ ] PEM file extracted for ElastAlert (`elastic-stack-ca.pem`)

- [ ] **Elasticsearch Security**
  - [ ] `xpack.security.enabled=true` in docker-compose.yml environment
  - [ ] `elasticsearch.yml` configured with TLS for both HTTP and transport layers
  - [ ] `elastic` superuser password reset and stored in `.env`
  - [ ] Healthcheck updated with `-k` flag for HTTPS and credentials
  - [ ] Elasticsearch is healthy: `docker compose ps` shows `(healthy)`

- [ ] **Service Authentication**
  - [ ] `kibana_system` password reset and stored in `.env`
  - [ ] `logstash_system` password reset and stored in `.env`
  - [ ] Kibana environment variables configured with `ELASTICSEARCH_PASSWORD` and `ELASTICSEARCH_SSL_*`
  - [ ] Logstash pipeline configured with `ssl => true`, `cacert`, `user`, `password`
  - [ ] ElastAlert config uses environment variable substitution for `$ELASTIC_PASSWORD`

- [ ] **RBAC & Authorization**
  - [ ] `logstash_writer` role created with write access to log indices
  - [ ] `viewer` role created with read-only access for dashboard users
  - [ ] `logstash_internal` user created with `logstash_writer` role
  - [ ] `dashboard_viewer` user created with `viewer` role
  - [ ] API key generated for Logstash and stored securely

- [ ] **Index Lifecycle Management**
  - [ ] ILM policy `elk-logs-policy` created with hot/warm/cold/delete phases
  - [ ] Composable index template `elk-logs-template` created with priority 1
  - [ ] Template applies ILM policy to all log indices automatically
  - [ ] No legacy `/_template/` API used (Elasticsearch 9.0 removed it)
  - [ ] Old conflicting templates deleted (e.g., `nginx-access-template`)

- [ ] **Services Running**
  - [ ] All containers healthy: `docker compose ps` shows all services `Up`
  - [ ] Kibana accessible at `https://your-server:5601` (login: elastic/password)
  - [ ] Logstash pipelines running without errors
  - [ ] ElastAlert connected to Elasticsearch

- [ ] **Security Best Practices**
  - [ ] `.env` file added to `.gitignore` (no passwords in Git)
  - [ ] All passwords stored securely (`.env`, .AWS Secrets Manager, etc.)
  - [ ] SSH access restricted to specific IP in Terraform Security Group
  - [ ] EC2 using IMDSv2 (`http_tokens = "required"`)
  - [ ] EBS volume encrypted

- [ ] **Terraform IaC**
  - [ ] `terraform/main.tf` uses AWS provider ~> 6.0
  - [ ] Remote state configured in S3 with DynamoDB locking
  - [ ] Variables substituted from `terraform.tfvars`
  - [ ] Security Group restricts SSH to your IP only
  - [ ] EC2 instance uses IAM role with SSM access
  - [ ] `terraform apply` plan reviewed before deployment

---

## ✅ Post-Deployment Validation

---

## ✅ Post-Deployment Validation

After bringing up all services, verify everything is working:

```bash
# Check all containers are running and healthy
docker compose ps

# Verify ES security is active
curl -u elastic:${ELASTIC_PASSWORD} \
  --cacert ./security/certs/elastic-stack-ca.pem \
  https://localhost:9200

# Verify ILM policy exists
curl -s https://localhost:9200/_ilm/policy/elk-logs-policy?pretty \
  -u elastic:${ELASTIC_PASSWORD} \
  --cacert ./security/certs/elastic-stack-ca.pem | jq '.elk-logs-policy.policy.phases | keys'

# Check Kibana can connect (view logs for errors)
docker compose logs kibana | tail -20

# Check Logstash can connect (view logs for errors)
docker compose logs logstash | tail -20

# Test a user with restricted permissions
curl -u logstash_internal:logstash_secure_password \
  --cacert ./security/certs/elastic-stack-ca.pem \
  https://localhost:9200/_security/user  # Should return 403 (forbidden)

# Verify API key works (from Step 3.1 response)
export API_KEY_ID="<from response>"
export API_KEY="<from response>"
curl -H "Authorization: ApiKey ${API_KEY_ID}:${API_KEY}" \
  --cacert ./security/certs/elastic-stack-ca.pem \
  https://localhost:9200
```

---

## 🧠 Concepts You Learned in Phase 5

**TLS/SSL Certificates with SANs (Subject Alternative Names):**
- Elasticsearch requires SANs in certificates for hostname verification to work
- Without SANs, tools like `elasticsearch-reset-password` fail with "No subject alternative names present"
- Always regenerate certs with `--dns` and `--ip` flags matching your deployment environment
- Generate with empty password (`--pass ""`) to avoid needing keystore password entries

**PKCS12 vs PEM Formats:**
- PKCS12 (.p12) is Elasticsearch's native binary certificate format (password-protected key + cert in one file)
- PEM is text-based format needed by OpenSSL tools and some clients (ElastAlert)
- Use `openssl pkcs12` command to convert between formats

**Environment Variables in Docker Compose:**
- Docker-compose.yml itself interpolates `${VAR}` from `env_file: .env`
- But config files (elasticsearch.yml, kibana.yml) do NOT automatically substitute variables
- Solution: Use environment variable references in docker-compose service definitions
- For ElastAlert2 and similar tools: Use Python/shell at startup to do template substitution

**Healthcheck Configuration:**
- Once TLS is enabled, healthchecks must use HTTPS and credentials
- Use `-k` flag in curl to skip cert verification (self-signed certs) or `--cacert path/to/ca.pem` to provide CA
- Healthchecks are crucial for `depends_on: condition: service_healthy` to work properly

**Index Template Priority:**
- Elasticsearch 8+/9+ use composable templates (`/_index_template/` API)
- Legacy `/_template/` API was removed in ES 9.0
- Multiple templates can match the same pattern — Elasticsearch requires same priority or explicit ordering
- Always set `"priority": 1` on new templates if old conflicting ones exist

**ILM Phases:**
- **Hot:** New indices, high ingestion rate, high priority (priority 100)
- **Warm:** Indexed data, can be merged/shrunk, medium priority (priority 50)
- **Cold:** Rarely accessed data, read-only, low priority (priority 0)
- **Delete:** Final phase, data purged after retention period
- **No `freeze` action in ES 8.0+** — use `searchable_snapshot` (requires snapshot repo) or accept less performance

**API Keys vs Username/Password:**
- API keys are rotatable, auditable, and can be scoped to specific indices
- Preferred for service-to-service authentication (Logstash → ES)
- Username/password still used for interactive dashboards (Kibana) and admin tasks (elastic user)

**Principle of Least Privilege (RBAC):**
- Logstash gets write-only role (no read, no delete, no user management)
- Dashboard viewers get read-only role (no write, no auth management)
- Elastic admin user remains superuser, used only for admin tasks
- Each service has minimal required permissions

**Production Security Hardening:**
- IMDSv2 (`http_tokens = required`) prevents SSRF attacks on EC2 metadata service
- Remote Terraform state (S3 + DynamoDB) prevents concurrent apply races
- EBS encryption at rest, SSH restricted to known IPs, no hardcoded secrets in Git

---

## 🎯 Project Complete — What You've Built

| Capability | Tool | ES 8+ Feature | Production Equivalent |
|---|---|---|---|
| Log collection | Filebeat | Built-in agents | Beats on every server |
| Log parsing | Logstash Grok | Ingest pipelines (alternative) | Logstash or ECS format |
| Storage + search | Elasticsearch | Full-text indexing, aggregations | ES cluster (3+ nodes) |
| Visualisation | Kibana dashboards | Canvas, Lens | Same / Grafana |
| Alerting | ElastAlert2 | Watcher (built-in) | ElastAlert2 / PagerDuty |
| Data retention | ILM policies | Hot/Warm/Cold/Delete phases | ILM + snapshots to S3 |
| Security | Built-in RBAC + TLS | X-Pack (included by default) | Okta SSO / LDAP + TLS |
| IaC | Terraform | N/A | Terraform + Ansible |
| Monitoring | Stack Monitoring | Built-in (paid) | Prometheus + Grafana |

---

## 🚀 Next Steps (Beyond Phase 5)

1. **High Availability:** Scale to 3-node ES cluster (1 master, 2 data)
2. **Snapshots:** Configure backup to S3 with automated retention
3. **SSO:** Integrate Okta/LDAP for team authentication instead of built-in realm
4. **Monitoring:** Set up Stack Monitoring (built-in) or Prometheus + Grafana
5. **Log Ingestion at Scale:** Replace Logstash with Kafka + Logstash or native ES connectors
6. **Compliance:** Enable audit logging (`xpack.security.audit.enabled: true`)
7. **Multi-Tenancy:** Implement spaces and role-based data access

---

