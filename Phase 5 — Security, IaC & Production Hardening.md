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

## Step 1 — Generate TLS Certificates

Elasticsearch ships with `elasticsearch-certutil` to generate self-signed certs.

```bash
#Step 1 — Generate CA (output to /tmp inside container): Use below cmd as it is without adding your own password

docker exec -it elasticsearch elasticsearch-certutil ca --out /tmp/elastic-stack-ca.p12 --pass ""

#Step 2 — Generate cert:

docker exec -it elasticsearch elasticsearch-certutil cert --ca /tmp/elastic-stack-ca.p12 --ca-pass "" --out /tmp/elastic-certificates.p12 --pass ""

#Step 3 — Copy files out to your host:

docker cp elasticsearch:/tmp/elastic-stack-ca.p12 ./security/certs/elastic-stack-ca.p12

docker cp elasticsearch:/tmp/elastic-certificates.p12 ./security/certs/elastic-certificates.p12

#Step 4 — Fix ownership so the elasticsearch user (UID 1000) can read them:
sudo chown 1000:0 ./security/certs/elastic-stack-ca.p12 ./security/certs/elastic-certificates.p12

sudo chmod 640 ./security/certs/elastic-stack-ca.p12 ./security/certs/elastic-certificates.p12

#Step 5 — Restart:
docker compose down && docker compose up

#Since both certs are now generated with empty passwords (--pass ""), Elasticsearch won't need any keystore password entries and should boot cleanly.
```

---

## Step 2 — Configure TLS & Security Settings

>Security (authentication + transport TLS) is **on by default**. You do not need to enable it — this step configures the HTTP TLS layer and customises settings for your Docker deployment.

### 2.1 Update `configs/elasticsearch.yml`

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

# TLS for transport layer (node-to-node communication)
xpack.security.transport.ssl.enabled: true
xpack.security.transport.ssl.verification_mode: certificate
xpack.security.transport.ssl.keystore.path: certs/elastic-certificates.p12
xpack.security.transport.ssl.truststore.path: certs/elastic-certificates.p12

path.data: /usr/share/elasticsearch/data
path.logs: /usr/share/elasticsearch/logs
```

### 2.2 Reset Built-in User Passwords

```bash
# Start ES with TLS configured
docker compose up -d elasticsearch

# Reset the elastic superuser password (auto-generates and prints it)
docker exec -it elasticsearch elasticsearch-reset-password -u elastic

# Or set it interactively (prompts you to type a password)
docker exec -it elasticsearch elasticsearch-reset-password -u elastic -i

# Reset kibana_system password
docker exec -it elasticsearch elasticsearch-reset-password -u kibana_system -i

# Reset logstash_system password
docker exec -it elasticsearch elasticsearch-reset-password -u logstash_system -i
```

> ⚠️ Save these passwords securely. Store them in `.env` (never commit this file).

```bash
# .env
ELASTIC_PASSWORD=your_elastic_password
KIBANA_SYSTEM_PASSWORD=your_kibana_system_password
LOGSTASH_SYSTEM_PASSWORD=your_logstash_system_password
```

---

## Step 3 — RBAC: Roles and Users

Define least-privilege roles for different consumers.

### `security/roles.yml`

```yaml
# Read-only role for dashboard viewers
elk_viewer:
  cluster:
    - monitor
  indices:
    - names:
        - "nginx-access-*"
        - "app-logs-*"
        - "syslog-*"
      privileges:
        - read
        - view_index_metadata

# Logstash write role — only write to log indices
logstash_writer:
  cluster:
    - manage_index_templates
    - monitor
    - manage_ilm
  indices:
    - names:
        - "nginx-access-*"
        - "app-logs-*"
        - "syslog-*"
      privileges:
        - write
        - create
        - create_index
        - manage
        - manage_ilm

# ElastAlert read role
elastalert_reader:
  cluster:
    - monitor
  indices:
    - names:
        - "nginx-access-*"
        - "app-logs-*"
        - "syslog-*"
        - "elastalert_status"
      privileges:
        - read
        - write
        - create_index
        - view_index_metadata
```

### Create Roles and Users via API

```bash
# Create the logstash_writer role
curl -X POST "https://localhost:9200/_security/role/logstash_writer" \
  -u elastic:${ELASTIC_PASSWORD} \
  -H 'Content-Type: application/json' \
  --cacert security/certs/elasticsearch.crt \
  -d '{
    "cluster": ["manage_index_templates", "monitor", "manage_ilm"],
    "indices": [{
      "names": ["nginx-access-*", "app-logs-*", "syslog-*"],
      "privileges": ["write", "create", "create_index", "manage", "manage_ilm"]
    }]
  }'

# Create a logstash user with that role
curl -X POST "https://localhost:9200/_security/user/logstash_internal" \
  -u elastic:${ELASTIC_PASSWORD} \
  -H 'Content-Type: application/json' \
  --cacert security/certs/elasticsearch.crt \
  -d '{
    "password": "logstash_secure_password",
    "roles": ["logstash_writer"],
    "full_name": "Logstash Internal User"
  }'

# Create a read-only dashboard viewer
curl -X POST "https://localhost:9200/_security/user/dashboard_viewer" \
  -u elastic:${ELASTIC_PASSWORD} \
  -H 'Content-Type: application/json' \
  --cacert security/certs/elasticsearch.crt \
  -d '{
    "password": "viewer_secure_password",
    "roles": ["elk_viewer"],
    "full_name": "Dashboard Viewer"
  }'

# Create an Elasticsearch API key for Logstash (preferred over username/password)
curl -X POST "https://localhost:9200/_security/api_key" \
  -u elastic:${ELASTIC_PASSWORD} \
  -H 'Content-Type: application/json' \
  --cacert security/certs/elasticsearch.crt \
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

---

## Step 4 — Index Lifecycle Management (ILM)

ILM automates the index lifecycle: **hot → warm → cold → delete**.

> For cold-tier cost savings, use `searchable_snapshot` (requires a snapshot repository) or rely on `set_priority: 0` + `readonly`.

### `ilm/policy.json`

```json
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
          // Note: freeze action removed — not supported in ES 8.x/9.x
          // For cold-tier archival, configure searchable_snapshot instead
          // if you have a snapshot repository set up.
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
```

### Apply the ILM Policy

```bash
# Create the ILM policy
curl -X PUT "https://localhost:9200/_ilm/policy/elk-logs-policy" \
  -u elastic:${ELASTIC_PASSWORD} \
  -H 'Content-Type: application/json' \
  --cacert security/certs/elasticsearch.crt \
  -d @ilm/policy.json

# Create a composable index template that applies this ILM policy automatically
# NOTE: Always use /_index_template/ (composable). The old /_template/ API
# was removed in ES 9.0.
curl -X PUT "https://localhost:9200/_index_template/elk-logs-template" \
  -u elastic:${ELASTIC_PASSWORD} \
  -H 'Content-Type: application/json' \
  --cacert security/certs/elasticsearch.crt \
  -d '{
    "index_patterns": ["nginx-access-*", "app-logs-*", "syslog-*"],
    "template": {
      "settings": {
        "number_of_shards": 1,
        "number_of_replicas": 0,
        "index.lifecycle.name": "elk-logs-policy",
        "index.lifecycle.rollover_alias": "logs"
      }
    }
  }'

# Verify the policy was created
curl -X GET "https://localhost:9200/_ilm/policy/elk-logs-policy?pretty" \
  -u elastic:${ELASTIC_PASSWORD} \
  --cacert security/certs/elasticsearch.crt

# Check ILM status for existing indices
curl -X GET "https://localhost:9200/nginx-access-*/_ilm/explain?pretty" \
  -u elastic:${ELASTIC_PASSWORD} \
  --cacert security/certs/elasticsearch.crt
```

---

## Step 5 — Final Terraform (Full IaC)

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

## Step 6 — Security Hardening Script

### `security/setup-tls.sh`

```bash
#!/bin/bash
# Run this inside the Elasticsearch container to set up TLS
set -e

CERT_DIR="/usr/share/elasticsearch/config/certs"
mkdir -p "$CERT_DIR"

echo "==> Generating CA..."
elasticsearch-certutil ca \
  --out "$CERT_DIR/elastic-stack-ca.p12" \
  --pass "" --silent

echo "==> Generating node certificate..."
elasticsearch-certutil cert \
  --ca "$CERT_DIR/elastic-stack-ca.p12" \
  --ca-pass "" \
  --out "$CERT_DIR/elastic-certificates.p12" \
  --pass "" --silent

echo "==> Exporting PEM files..."
openssl pkcs12 \
  -in "$CERT_DIR/elastic-certificates.p12" \
  -clcerts -nokeys \
  -out "$CERT_DIR/elasticsearch.crt" \
  -passin pass:""

openssl pkcs12 \
  -in "$CERT_DIR/elastic-certificates.p12" \
  -nocerts -nodes \
  -out "$CERT_DIR/elasticsearch.key" \
  -passin pass:""

chmod 600 "$CERT_DIR/elasticsearch.key"
echo "==> TLS setup complete. Certs in $CERT_DIR"
```

---

## ✅ Phase 5 Checklist

- [ ] TLS certificates generated and mounted into Elasticsearch container
- [ ] `elasticsearch.yml` updated with TLS config (security is on by default in ES 8+/9+)
- [ ] `elastic` superuser password reset with `elasticsearch-reset-password` (not the deprecated `setup-passwords`)
- [ ] `logstash_writer` role and user created
- [ ] `elk_viewer` role and user created
- [ ] API key generated for Logstash → ES authentication
- [ ] ILM policy `elk-logs-policy` created (hot→warm→cold→delete) — **no `freeze` action**
- [ ] Composable index template (`/_index_template/`) applying ILM to all log indices — **not the legacy `/_template/` API**
- [ ] Terraform uses remote S3 backend with DynamoDB state locking
- [ ] AWS provider version set to `~> 6.0`
- [ ] EC2 uses IMDSv2 (`http_tokens = "required"`)
- [ ] EBS volume encrypted
- [ ] SSH restricted to your IP only in Security Group
- [ ] `.env` in `.gitignore`, no secrets in any committed file

---

## 🧠 Concepts You Learned in Phase 5

**Built-in Security (formerly X-Pack)** is Elastic's security layer — authentication, authorisation, TLS, audit logging. Enabled by default from ES 8.0. "X-Pack" as a separate product no longer exists; all security features are bundled and on by default.

**ILM (Index Lifecycle Management)** automatically transitions indices through hot → warm → cold → delete phases. Analogous to Commvault retention policies — data is retained for a defined period then automatically pruned. The `freeze` action was removed in 8.0/9.0; cold-phase data reduction is now done via `searchable_snapshot` or `readonly`.

**RBAC (Role-Based Access Control)** limits what each user/service can do in ES — principle of least privilege. Logstash only gets write permissions to its own indices; it can't query or delete.

**API keys** are preferred over username/password for service-to-service auth — they're rotatable, auditable, and can be scoped to specific indices.

**IMDSv2** (`http_tokens = required`) prevents SSRF attacks from accessing the EC2 metadata service — a real AWS production hardening requirement enforced by AWS Security Hub.

**Remote Terraform state** (S3 + DynamoDB locking) prevents two engineers from running `terraform apply` simultaneously and corrupting state — essential in team environments.

**Composable index templates** (`_index_template` API) replaced the legacy `_template` API, which was fully removed in ES 9.0.

---

## 🎯 Project Complete — What You've Built

| Capability | Tool | Production Equivalent |
|---|---|---|
| Log collection | Filebeat | Beats agents on every server |
| Log parsing | Logstash Grok | Logstash / Kafka + Logstash |
| Storage + search | Elasticsearch | ES cluster (3+ nodes) |
| Visualisation | Kibana dashboards | Same |
| Alerting | ElastAlert2 | ElastAlert2 / PagerDuty integration |
| Data retention | ILM policies | ILM + snapshots to S3 |
| Security | Built-in TLS + RBAC | Built-in + SSO/LDAP integration |
| IaC | Terraform | Terraform + Ansible (config) |

---

