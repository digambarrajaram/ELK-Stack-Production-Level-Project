# ELK Stack — Production-Level Project

> **Built by Digambar Rajaram** | DevOps & Infrastructure Engineer  
> A hands-on, production-style ELK Stack implementation covering log ingestion, dashboards, alerting, and IaC hardening.

---

## 🗂️ Project Structure

```
elk-stack-project/
├── README.md                     ← You are here
├── phase-1-infrastructure/
│   ├── README.md                 ← Setup guide
│   ├── docker-compose.yml
│   ├── terraform/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── configs/
│       ├── elasticsearch.yml
│       ├── kibana.yml
│       └── logstash.yml
├── phase-2-log-ingestion/
│   ├── README.md
│   ├── filebeat/
│   │   └── filebeat.yml
│   └── logstash/
│       ├── pipelines/
│       │   ├── nginx.conf
│       │   ├── app-logs.conf
│       │   └── syslog.conf
│       └── patterns/
│           └── custom-patterns
├── phase-3-kibana-dashboards/
│   ├── README.md
│   └── dashboards/
│       ├── infra-health.ndjson
│       ├── nginx-analytics.ndjson
│       └── error-rate.ndjson
├── phase-4-alerting/
│   ├── README.md
│   ├── elastalert2/
│   │   ├── config.yml
│   │   └── rules/
│   │       ├── high-error-rate.yml
│   │       ├── ssh-brute-force.yml
│   │       └── cpu-spike.yml
│   └── watcher/
│       └── error-spike-watcher.json
└── phase-5-hardening/
    ├── README.md
    ├── security/
    │   ├── setup-tls.sh
    │   └── roles.yml
    └── ilm/
        └── policy.json
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
| [Phase 1](./phase-1-infrastructure/README.md) | Infrastructure Setup | Docker, Terraform, AWS EC2 | 🟢 Start here |
| [Phase 2](./phase-2-log-ingestion/README.md) | Log Ingestion Pipelines | Filebeat, Logstash, Grok | 🔵 Core skills |
| [Phase 3](./phase-3-kibana-dashboards/README.md) | Kibana Dashboards | Lens, TSVB, Maps | 🔵 Portfolio-ready |
| [Phase 4](./phase-4-alerting/README.md) | Alerting & Detection | ElastAlert2, Watcher | 🟠 Interview gold |
| [Phase 5](./phase-5-hardening/README.md) | Security & Hardening | X-Pack TLS, ILM, RBAC | 🔴 Production-grade |

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
