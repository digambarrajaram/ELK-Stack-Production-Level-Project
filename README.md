# ELK Stack — Production-Level Project

> **Built by Digambar Rajaram** | DevOps & Infrastructure Engineer  
> A hands-on, production-style ELK Stack implementation covering log ingestion, dashboards, alerting, and IaC hardening.

---

## 🗂️ Project Structure

```
ELK_Stack/
├── README.md                     ← You are here
├── .env.example                  ← Environment variables template
├── .env                          ← Your actual secrets (not in git)
├── docker-compose.yml            ← Main service orchestration
├── elk_setup.sh                  ← Setup script
├── configs/
│   ├── elasticsearch.yml         ← ES configuration with TLS
│   ├── kibana.yml                ← Kibana configuration
│   ├── logstash.yml              ← Logstash configuration
│   └── pipelines.yml             ← Logstash pipeline config
├── phase-1-infrastructure/
│   └── terraform/                ← Empty stubs (use terraform/ instead)
├── phase-2-log-ingestion/
│   ├── filebeat/
│   │   └── filebeat.yml          ← Filebeat log collection config
│   └── logstash/
│       └── pipelines/
│           └── combined.conf     ← Main Logstash pipeline with Grok filters
├── phase-3-kibana-dashboards/
│   ├── dashboards/
│   │   ├── Dashboard_Snapshots/  ← Dashboard screenshot images
│   │   ├── export.ndjson         ← Exported dashboard objects
│   │   └── kql-cheatsheet.md     ← KQL query reference
├── phase-4-alerting/
│   ├── elastalert2/
│   │   ├── config.yaml.tpl       ← ElastAlert2 config template (env vars substituted)
│   │   ├── config.yml            ← ElastAlert2 config (without env substitution)
│   │   ├── smtp_auth.yaml        ← SMTP credentials
│   │   ├── rules/
│   │   │   ├── high-error-rate.yml
│   │   │   ├── ssh-brute-force.yml
│   │   │   ├── app-error-spike.yml
│   │   │   ├── slow-response-time.yml
│   │   │   └── disk-usage-warning.yml
│   │   └── watcher/
│   │       └── error-spike-watcher.json
│   └── test-all-alerts.sh        ← Test script for alert rules
├── phase-5-hardening/           ← (not a separate directory, see below)
├── ilm/
│   └── policy.json               ← Index Lifecycle Management policy
├── security/
│   └── roles.yml                 ← RBAC role definitions
└── terraform/
    ├── main.tf                   ← Main Terraform configuration
    ├── variables.tf              ← Terraform input variables
    ├── outputs.tf                ← Terraform outputs
    ├── provider.tf               ← AWS provider configuration
    ├── remote_backend.tf         ← S3 backend configuration
    ├── ec2/
    │   ├── main.tf               ← EC2 instance resources
    │   ├── output.tf             ← EC2 outputs
    │   ├── variable.tf           ← EC2 variables
    │   └── user-data.sh          ← EC2 bootstrap script
    └── vpc/
        ├── main.tf               ← VPC resources
        ├── output.tf             ← VPC outputs
        └── variable.tf           ← VPC variables
```

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    AWS EC2 (Terraform)                   │
│                                                         │
│  Log Sources          Pipeline            Storage+UI    │
│  ┌──────────┐        ┌──────────┐        ┌───────────┐ │
│  │  Nginx   │──►     │          │        │           │ │
│  │  App     │──► FB ─► Logstash ─►──────►│   Elastic │ │
│  │  Syslog  │──►     │  Grok    │        │   search  │ │
│  └──────────┘        └──────────┘        └─────┬─────┘ │
│                                                 │       │
│                        ┌────────────────────────┤       │
│                        ▼                        ▼       │
│                  ┌──────────┐           ┌──────────┐    │
│                  │ElastAlert│           │  Kibana  │    │
│                  │  Rules   │           │Dashboards│    │
│                  └────┬─────┘           └──────────┘    │
│                       │                                  │
│                  ┌────▼─────┐                           │
│                  │  Slack / │                           │
│                  │  Email   │                           │
│                  └──────────┘                           │
└─────────────────────────────────────────────────────────┘
```

---

## 📋 Phases Overview

| Phase | Topic | Key Skills | Status |
|-------|-------|-----------|--------|
| [Phase 1](./Phase%201%20—%20Infrastructure%20Setup.md) | Infrastructure Setup | Docker, Terraform, AWS EC2 | 🟢 Start here |
| [Phase 2](./Phase%202%20—%20Log%20Ingestion%20Pipelines.md) | Log Ingestion Pipelines | Filebeat, Logstash, Grok | 🔵 Core skills |
| [Phase 3](./Phase%203%20—%20Kibana%20Dashboards%20&%20Visualizations.md) | Kibana Dashboards | Lens, TSVB, Maps | 🔵 Portfolio-ready |
| [Phase 4](./Phase%204%20—%20Alerting%20&%20Anomaly%20Detection.md) | Alerting & Detection | ElastAlert2, Watcher | 🟠 Interview gold |
| [Phase 5](./Phase%205%20—%20Security,%20IaC%20&%20Production%20Hardening.md) | Security & Hardening | X-Pack TLS, ILM, RBAC | 🔴 Production-grade |

---

## 🛠️ Prerequisites

- AWS account with an EC2 key pair
- Terraform >= 1.5 installed locally
- Docker & Docker Compose v2 on the EC2 instance
- Basic Linux CLI familiarity (you already have this ✅)

---

## 💡 Interview Talking Points This Project Unlocks

- *"I built a centralized log aggregation pipeline ingesting Nginx, application, and OS logs."*
- *"I wrote Logstash Grok pipelines to parse and enrich log data before indexing."*
- *"I created Kibana dashboards tracking error rates, request latency, and geo-traffic in real time."*
- *"I implemented ElastAlert2 rules for anomaly detection with Slack notifications — sub-5-min MTTD."*
- *"I hardened the cluster with X-Pack TLS, RBAC, and index lifecycle policies to manage storage costs."*
- *"I provisioned the entire stack on AWS using Terraform — infrastructure as code end to end."*

---

## 📌 Tech Stack

`Elasticsearch 8.x` · `Logstash 8.x` · `Kibana 8.x` · `Filebeat 8.x` · `ElastAlert2` · `Docker Compose` · `Terraform` · `AWS EC2` · `Slack Webhooks`

---

*Star ⭐ this repo if it helped you. Contributions and suggestions welcome.*
