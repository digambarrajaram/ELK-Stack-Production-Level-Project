# ELK Stack — Complete Guide for Professionals & Interview Preparation

> **ELK Stack** = **E**lasticsearch + **L**ogstash + **K**ibana (+ **Beats** as the modern 4th pillar)

---

## Table of Contents

1. [What is the ELK Stack?](#1-what-is-the-elk-stack)
2. [Core Architecture](#2-core-architecture)
3. [Component Definitions](#3-component-definitions)
4. [Configuration Files — Deep Dive](#4-configuration-files--deep-dive)
5. [Real-Time Data Flow Example](#5-real-time-data-flow-example)
6. [Architecture & YAML Configuration Flow Diagram](#6-architecture--yaml-configuration-flow-diagram)
7. [Critical Inter-Component Connections](#7-critical-inter-component-connections)
8. [Security (X-Pack) Notes](#8-security-x-pack-notes)
9. [Production Best Practices](#9-production-best-practices)
10. [How Professionals Handle YAML Files](#10-how-professionals-handle-yaml-files)
11. [Interview Q&A](#11-interview-qa)

---

## 1. What is the ELK Stack?

The ELK Stack is a collection of three (now four) open-source tools built by **Elastic** for centralized log management, real-time search, and data visualization.

| Letter | Tool | Role |
|--------|------|------|
| **E** | Elasticsearch | Distributed search and analytics database |
| **L** | Logstash | Data processing pipeline (collect, parse, transform) |
| **K** | Kibana | Web UI for visualization and dashboards |
| **B** | Beats | Lightweight data shippers installed on source servers |

### Why Use ELK?

- **Centralization** — Collect logs from hundreds of servers in one place
- **Real-time** — Logs are searchable within seconds of generation
- **Scalability** — Elasticsearch clusters can store petabytes of data
- **Visualization** — Kibana turns raw JSON into charts, maps, and dashboards
- **Open Source** — Core features are free; advanced features via X-Pack/Elastic license

---

## 2. Core Architecture

```
[ Application Servers ]
        │
        ▼  (Generate Log Files)
    [ Beats ]          ← Lightweight shippers (Filebeat, Metricbeat, etc.)
        │
        ▼  (Ship raw logs over network)
   [ Logstash ]        ← Parses, filters, transforms data
        │
        ▼  (Send clean structured JSON)
[ Elasticsearch ]      ← Stores, indexes, and makes data searchable
        │
        ▼  (Reads indexed data)
    [ Kibana ]         ← Visualizes data for engineers/analysts
```

### Data Flow Summary

```
Raw Text Log  →  Beats  →  Logstash (Parse)  →  Elasticsearch (Store)  →  Kibana (View)
```

---

## 3. Component Definitions

### 🟡 Beats
**Definition:** Ultra-lightweight data shippers written in Go. Installed directly on source servers. They have a single job: watch files or system metrics and forward them.

**Types of Beats:**
- **Filebeat** — Ships log files (most common)
- **Metricbeat** — Ships system and service metrics (CPU, RAM, disk)
- **Packetbeat** — Ships network packet data
- **Auditbeat** — Ships Linux audit framework data
- **Winlogbeat** — Ships Windows Event Logs

**Key Concept — Registrar:** Filebeat keeps an internal registry file that records the exact byte offset of the last line it read. If the server restarts, Filebeat resumes from that exact point — guaranteeing zero data loss.

---

### 🔵 Logstash
**Definition:** A server-side data processing pipeline. It simultaneously ingests data from many sources, transforms it, and sends it to your designated output.

**Pipeline Structure (3 mandatory stages):**

| Stage | Purpose |
|-------|---------|
| `input {}` | Where does data come from? (Beats, files, databases, Kafka, etc.) |
| `filter {}` | How should data be cleaned/structured? (Grok, mutate, date, etc.) |
| `output {}` | Where should processed data go? (Elasticsearch, S3, stdout, etc.) |

**Key Concept — Grok Filter:** A pattern-matching plugin that reads a raw text string and breaks it into named fields. Think of it as regex with human-readable named patterns.

---

### 🟢 Elasticsearch
**Definition:** A distributed, RESTful search and analytics engine built on top of Apache Lucene. It stores data as JSON documents and makes them searchable in near real-time.

**Key Concepts:**

| Term | Definition |
|------|-----------|
| **Cluster** | A group of one or more Elasticsearch nodes working together |
| **Node** | A single running instance of Elasticsearch |
| **Index** | A collection of documents (similar to a database table) |
| **Shard** | A subset of an index; Elasticsearch splits large indexes across shards |
| **Replica** | A copy of a shard for redundancy and read performance |
| **Document** | A single JSON record stored in an index |

---

### 🟣 Kibana
**Definition:** The visualization front-end for the Elastic Stack. Kibana connects to Elasticsearch and provides a web interface to search logs, build dashboards, and create alerts.

**Key Features:**
- **Discover** — Raw log search and filtering
- **Dashboard** — Multi-panel visual overviews
- **Lens** — Drag-and-drop chart builder
- **Alerts** — Rule-based notifications
- **Dev Tools** — Direct Elasticsearch API console

---

## 4. Configuration Files — Deep Dive

### 🟡 filebeat.yml

```yaml
# 1. Where to gather the raw logs (Input Section)
filebeat.inputs:
- type: log
  enabled: true
  paths:
    - /var/log/apache2/access.log   # File to watch

# 2. Where to ship the logs (Output Section)
output.logstash:
  hosts: ["logstash-server-ip:5044"]  # Must match Logstash input port
```

**Parameter Explanations:**

| Parameter | What It Does |
|-----------|-------------|
| `type: log` | Tells Filebeat to watch standard log files line by line |
| `enabled: true` | Activates this input configuration block |
| `paths` | List of file paths (supports wildcards like `/var/log/*.log`) |
| `output.logstash.hosts` | The network address of the Logstash server to ship data to |

> **Note:** Filebeat can also output directly to Elasticsearch, skipping Logstash — useful for simple setups where no parsing is needed.

---

### 🔵 logstash.yml (System Settings)

```yaml
node.name: logstash-node-1
path.data: /var/lib/logstash
pipeline.workers: 4
queue.type: persisted
```

**Parameter Explanations:**

| Parameter | What It Does |
|-----------|-------------|
| `node.name` | A unique, human-readable identifier for this Logstash instance |
| `path.data` | Directory where Logstash stores its internal persistent state and queues |
| `pipeline.workers` | Number of CPU threads allocated to process data concurrently; set to number of CPU cores |
| `queue.type` | `memory` = fast but data lost on crash; `persisted` = disk-backed, survives restarts |

---

### 🔵 logstash-sample.conf (Pipeline Config)

```ruby
input {
  beats {
    port => 5044           # Open doorway listening for Filebeat connections
  }
}

filter {
  grok {
    match => {
      "message" => "%{COMBINEDAPACHELOG}"  # Parse Apache log format
    }
  }
  date {
    match => ["timestamp", "dd/MMM/yyyy:HH:mm:ss Z"]  # Parse timestamp field
    target => "@timestamp"
  }
}

output {
  elasticsearch {
    hosts => ["localhost:9200"]     # Where to send structured data
    index => "apache-logs-%{+YYYY.MM.dd}"  # Daily index naming
  }
}
```

**Stage-by-Stage Breakdown:**

**INPUT:**
- Opens port `5044` on the Logstash server
- Waits for Filebeat to connect and stream log lines
- Each line arrives as a raw string in the `message` field

**FILTER (Grok):**
- `%{COMBINEDAPACHELOG}` is a built-in Grok pattern that matches the Apache Combined Log Format
- It breaks a raw line like `192.168.1.50 - - [20/May/2026:12:45:00] "POST /login HTTP/1.1" 401 532` into:
  ```json
  {
    "clientip": "192.168.1.50",
    "timestamp": "20/May/2026:12:45:00",
    "verb": "POST",
    "request": "/login",
    "response": "401",
    "bytes": "532"
  }
  ```

**OUTPUT:**
- Forwards the clean JSON document to Elasticsearch on port `9200`
- Creates daily indexes like `apache-logs-2026.05.20`

---

### 🟢 elasticsearch.yml

```yaml
# Cluster Identity
cluster.name: my-production-cluster
node.name: node-1

# Networking
network.host: 0.0.0.0

# Discovery (How nodes find each other)
discovery.seed_hosts: ["192.168.1.10", "192.168.1.11"]
cluster.initial_master_nodes: ["node-1"]

# Storage
path.data: /var/data/elasticsearch
path.logs: /var/log/elasticsearch

# Security
xpack.security.enabled: true
```

**Parameter Explanations:**

| Parameter | What It Does |
|-----------|-------------|
| `cluster.name` | Only nodes sharing this exact name can join this cluster |
| `node.name` | Unique human-readable name for this specific server instance |
| `network.host: 0.0.0.0` | Binds Elasticsearch to all available network interfaces (accepts connections from any IP) |
| `discovery.seed_hosts` | List of other node IPs this node contacts first to find the cluster |
| `cluster.initial_master_nodes` | Specifies which nodes are eligible to be elected as master during the very first cluster startup — remove this after cluster is running |
| `path.data` | Where Elasticsearch stores its index data (use a dedicated disk in production) |
| `path.logs` | Where Elasticsearch writes its own application logs |
| `xpack.security.enabled` | Activates authentication, role-based access control (RBAC), and TLS encryption |

> **Important:** `cluster.initial_master_nodes` is a **bootstrap setting only**. Remove it from config after the cluster has formed to prevent split-brain scenarios.

---

### 🟣 kibana.yml

```yaml
# Server Settings
server.port: 5601
server.host: "0.0.0.0"

# Elasticsearch Connection
elasticsearch.hosts: ["http://localhost:9200"]
elasticsearch.username: "kibana_system"
elasticsearch.password: "your_secure_password"

# Optional: Kibana Encryption Key
xpack.encryptedSavedObjects.encryptionKey: "a-32-char-minimum-secret-key-here"
```

**Parameter Explanations:**

| Parameter | What It Does |
|-----------|-------------|
| `server.port` | The web port users open in their browser (default: 5601) |
| `server.host: "0.0.0.0"` | Makes Kibana accessible from any external computer (not just localhost) |
| `elasticsearch.hosts` | The address(es) of the Elasticsearch cluster Kibana reads data from |
| `elasticsearch.username` | The built-in system service account Kibana uses to authenticate to Elasticsearch |
| `elasticsearch.password` | The password for that system account (set during `elasticsearch-setup-passwords` step) |
| `xpack.encryptedSavedObjects.encryptionKey` | Encrypts saved searches, dashboards, and alert rules at rest |

> **Note:** `kibana_system` is a built-in Elasticsearch user specifically scoped for Kibana's internal operations. Never use the `elastic` superuser in `kibana.yml`.

---

## 5. Real-Time Data Flow Example

### Scenario: Failed Login Attempt Tracking

A user at IP `192.168.1.50` enters the wrong password on an e-commerce website.

---

**Step 1 — Log is Born on the Web Server**

Apache writes this raw line to `/var/log/apache2/access.log`:
```
192.168.1.50 - - [20/May/2026:12:45:00] "POST /login HTTP/1.1" 401 532
```

---

**Step 2 — Filebeat Ships the Log**

- Filebeat's harvester detects the new line
- It checks the **registrar** to confirm this line hasn't been sent before
- It ships the raw line over TCP to `logstash-server:5044`
- It updates the registrar with the new byte offset

---

**Step 3 — Logstash Receives and Processes**

*logstash.yml kicks in first:*
- `queue.type: persisted` — Logstash immediately saves the incoming raw line to disk (safe from crashes)
- `pipeline.workers: 4` — Assigns this log to one of 4 available processing threads

*logstash-sample.conf runs the pipeline:*
- **Input stage:** Line enters through `beats { port => 5044 }`
- **Filter stage:** Grok parses the raw text into structured JSON:
  ```json
  {
    "clientip": "192.168.1.50",
    "timestamp": "20/May/2026:12:45:00",
    "verb": "POST",
    "request": "/login",
    "response": "401",
    "bytes": "532"
  }
  ```
- **Output stage:** Clean JSON is forwarded to `localhost:9200`

---

**Step 4 — Elasticsearch Stores and Indexes**

- Data arrives at `network.host: 0.0.0.0` on port 9200
- `xpack.security.enabled: true` checks Logstash's credentials — if valid, data is accepted
- `node-1` writes the document to the index and notifies partner nodes in `discovery.seed_hosts`
- The log is now indexed and **searchable in milliseconds**

---

**Step 5 — Engineer Views the Alert in Kibana**

- Engineer opens `http://elk-server:5601` in their browser
- Kibana uses `elasticsearch.username: kibana_system` + `elasticsearch.password` to silently authenticate
- Kibana queries Elasticsearch for documents where `response: 401`
- A **red flashing bar chart** shows 47 failed logins from `192.168.1.50` in the last 10 minutes
- Total time from failed login to visible alert: **< 2 seconds**

---

## 6. Architecture & YAML Configuration Flow Diagram

```
[ Web Server / Application Server ]
          │
          ▼  (Writes raw text to access.log)
┌─────────────────────────────────────────────────────────┐
│  🟡 FILEBEAT  (filebeat.yml)                            │
│  ├── paths: ["/var/log/apache2/access.log"]             │
│  └── output.logstash.hosts: ["logstash-ip:5044"] ──────┐│
└────────────────────────────────────────────────────────│┘
                                                         │
         ┌───────────────────────────────────────────────┘
         ▼  (Sends raw log line over TCP port 5044)
┌─────────────────────────────────────────────────────────┐
│  🔵 LOGSTASH SYSTEM  (logstash.yml)                     │
│  ├── queue.type: persisted  → Saves to path.data disk   │
│  └── pipeline.workers: 4   → Parallel processing        │
└─────────────────────────────────────────────────────────┘
                       │
                       ▼  (Hands data to pipeline engine)
┌─────────────────────────────────────────────────────────┐
│  🔵 LOGSTASH PIPELINE  (logstash-sample.conf)           │
│  ├── input  { beats { port => 5044 } }                  │
│  ├── filter { grok { ...parses text to JSON... } }      │
│  └── output { elasticsearch { hosts => ["es:9200"] } }──┐
└───────────────────────────────────────────────────────│─┘
                                                        │
         ┌──────────────────────────────────────────────┘
         ▼  (Sends clean JSON to port 9200)
┌─────────────────────────────────────────────────────────┐
│  🟢 ELASTICSEARCH  (elasticsearch.yml)                  │
│  ├── network.host: 0.0.0.0  → Listens on all interfaces │
│  ├── xpack.security.enabled: true  ◄──────────────────┐ │
│  ├── cluster.name: my-production-cluster               │ │
│  └── discovery.seed_hosts: [node2, node3]              │ │
└────────────────────────────────────────────────────────│─┘
                                                         │
         ┌───────────────────────────────────────────────┘
         │  (Authenticates Kibana as a trusted system service)
┌────────┴────────────────────────────────────────────────┐
│  🟣 KIBANA  (kibana.yml)                                │
│  ├── server.port: 5601          → Browser access point  │
│  ├── elasticsearch.hosts: ["http://es:9200"]            │
│  ├── elasticsearch.username: "kibana_system"  ─────────►│── authenticates against xpack.security
│  └── elasticsearch.password: "secure_password"         │
└─────────────────────────────────────────────────────────┘
          ▲
          │  (Views dashboards)
[ Security Engineer / Analyst ]
```

### Key Cross-Component Reference Points

```
filebeat.yml                    logstash-sample.conf
────────────────────────────────────────────────────
output.logstash.hosts:          input { beats {
  ["logstash-ip:5044"]    ───►    port => 5044 } }

logstash-sample.conf            elasticsearch.yml
────────────────────────────────────────────────────
output { elasticsearch {        network.host: 0.0.0.0
  hosts => ["es:9200"] } } ───► (listening on 9200)

kibana.yml                      elasticsearch.yml
────────────────────────────────────────────────────
elasticsearch.username:         xpack.security.
  "kibana_system"         ───►    enabled: true
elasticsearch.password:
  "your_secure_password"
```

---

## 7. Critical Inter-Component Connections

There are **3 critical handshakes** you must be able to explain in any interview:

### Handshake 1 — Beats → Logstash
- `output.logstash.hosts` in `filebeat.yml` **must match** `port => 5044` in `logstash-sample.conf`
- If the port number differs, Filebeat has nowhere to send data → silent data loss

### Handshake 2 — Logstash → Elasticsearch
- `output { elasticsearch { hosts => [...] } }` in the pipeline conf **must point to** a valid IP bound by `network.host` in `elasticsearch.yml`
- If Elasticsearch isn't reachable, Logstash queues data (if `queue.type: persisted`) and retries

### Handshake 3 — Kibana → Elasticsearch (Security Bridge)
- When `xpack.security.enabled: true` in `elasticsearch.yml`, Elasticsearch locks all API endpoints
- Kibana cannot operate without valid credentials
- `elasticsearch.username` and `elasticsearch.password` in `kibana.yml` provide those credentials
- The `kibana_system` user has only the permissions Kibana needs — principle of least privilege

---

## 8. Security (X-Pack) Notes

X-Pack is Elastic's security module. When enabled, it provides:

| Feature | Description |
|---------|-------------|
| **Authentication** | Users must log in with username and password |
| **RBAC** | Role-Based Access Control — users only see data they're authorized for |
| **TLS/SSL** | Encrypts data in transit between all components |
| **Audit Logging** | Logs all access to Elasticsearch for compliance |
| **Field-Level Security** | Hide specific fields from specific users |

### Enabling Basic Security (Minimal Production Config)

**elasticsearch.yml additions:**
```yaml
xpack.security.enabled: true
xpack.security.transport.ssl.enabled: true
xpack.security.transport.ssl.verification_mode: certificate
xpack.security.transport.ssl.keystore.path: elastic-certificates.p12
xpack.security.transport.ssl.truststore.path: elastic-certificates.p12
```

### Setting Up Built-in Users
After first start, run:
```bash
bin/elasticsearch-setup-passwords interactive
```
This sets passwords for: `elastic`, `kibana_system`, `logstash_system`, `beats_system`, `apm_system`, `remote_monitoring_user`

### JVM Heap Size
> **Important:** Memory settings live in `jvm.options`, NOT in `elasticsearch.yml`.

```
# /etc/elasticsearch/jvm.options
-Xms4g    # Minimum heap (set equal to max)
-Xmx4g    # Maximum heap
```

**Rule of thumb:** Set heap to **50% of available RAM**, but never more than **31GB** (JVM compressed pointers limit).

---

## 9. Production Best Practices

### Storage
- **Always** separate `path.data` and `path.logs` onto dedicated storage disks
- Use SSDs for `path.data` — Elasticsearch is I/O intensive
- Mount a separate volume for Logstash `path.data` (persisted queues can grow large)

### Cluster Sizing (Minimum Production Setup)
```
3 Master-Eligible Nodes    → Prevents split-brain (always use odd numbers)
2+ Data Nodes              → Store and serve indexed data
1 Coordinating Node        → Routes requests (optional, improves performance)
```

### Index Lifecycle Management (ILM)
- Hot phase: Fast SSDs, recent data, active writes
- Warm phase: Slower disks, slightly older data, read-only
- Cold phase: Cheapest storage, old data, rarely queried
- Delete phase: Automatic cleanup after retention period

### Monitoring
- Use **Metricbeat** to collect ELK stack metrics and ship them to a dedicated monitoring cluster
- Never monitor a cluster using itself (if it goes down, monitoring dies too)

### Logstash Performance Tips
- Set `pipeline.workers` equal to the number of CPU cores
- Use `pipeline.batch.size: 125` (default) as a starting point
- Enable `queue.type: persisted` with adequate disk space for all production deployments

---

## 10. How Professionals Handle YAML Files

Interviewers do **not** expect rote memorization of configuration files. They want to see architectural understanding.

### The Professional Approach

1. **Understand Core Blocks** — Every YAML file is organized into logical sections. Know the sections, not every line.
2. **Use Templates** — DevOps engineers modify default templates provided by Elastic, not write from scratch.
3. **Leverage Documentation** — [https://www.elastic.co/guide/](https://www.elastic.co/guide/) is always the authoritative source.
4. **Use Automation** — Ansible, Terraform, and Puppet manage YAML configs at scale.
5. **IDE Extensions** — VS Code YAML extensions autocomplete parameters and catch syntax errors.

### How to Answer in an Interview

> *"In a production environment, I use standard templates and automation tools like Ansible or Terraform rather than writing YAML from scratch. However, I am deeply familiar with the core parameters required to get the stack running — cluster identity, networking, discovery, security, and the pipeline's input-filter-output structure."*

---

## 11. Interview Q&A

### Architecture Questions

**Q: Explain the ELK Stack architecture and the role of each component.**

A: The ELK Stack has four main components. **Beats** (like Filebeat) are lightweight agents installed on servers that watch log files and ship raw text data. **Logstash** receives that raw data, parses it using filters like Grok, transforms it into structured JSON, and forwards it to Elasticsearch. **Elasticsearch** is a distributed database that stores, indexes, and makes data searchable in near real-time. **Kibana** is the visualization layer that connects to Elasticsearch and lets engineers build dashboards and run searches.

---

**Q: What is the difference between Logstash and Beats? Why use both?**

A: Beats are ultra-lightweight shippers — they use minimal CPU and RAM. Their only job is to read files and forward raw data. Logstash is resource-heavy but powerful — it parses, enriches, and transforms data. In production, we use Beats on every application server (where resources are precious) to ship raw data to a centralized Logstash instance for heavy processing. This keeps the application servers light and centralizes all parsing logic.

---

**Q: What is a Grok filter and when would you use it?**

A: Grok is a Logstash filter plugin that matches unstructured text against named patterns and extracts fields from it. I use it to parse log formats like Apache Combined Log Format, syslog, or any custom application log. For example, a raw Apache log line becomes a structured JSON document with individual fields for IP address, HTTP method, status code, and response size. This structured data is what Kibana can then filter, aggregate, and visualize.

---

**Q: What is `cluster.initial_master_nodes` and when should you remove it?**

A: This parameter is a bootstrap-only setting that tells Elasticsearch which nodes are eligible to be elected master during the very first time a cluster forms. It prevents split-brain during initial startup. After the cluster has formed successfully and all nodes have joined, you should **remove this setting** from the config file. If left in place, it can cause problems during future restarts by confusing the cluster about which nodes should initiate a new election.

---

**Q: How does Kibana authenticate to Elasticsearch when security is enabled?**

A: When `xpack.security.enabled: true` is set in elasticsearch.yml, Elasticsearch locks all API endpoints and requires authentication. Kibana uses the credentials defined in kibana.yml — specifically `elasticsearch.username: kibana_system` and `elasticsearch.password` — to authenticate itself as a trusted system service. The `kibana_system` user is a built-in account with a minimal set of permissions scoped specifically for Kibana's internal operations. It's best practice to never use the `elastic` superuser account in kibana.yml.

---

### Troubleshooting Questions

**Q: Filebeat is running but no data appears in Kibana. How do you troubleshoot?**

A: I work through the pipeline systematically:
1. Check Filebeat logs — is it actually reading the file? Registry issue?
2. Check network connectivity — can Filebeat reach `logstash-ip:5044`?
3. Check Logstash logs — is it receiving data? Are there Grok parse failures?
4. Check Elasticsearch — is the index being created? Use `GET /_cat/indices` via Dev Tools.
5. Check Kibana — is the index pattern configured correctly? Is the time range set correctly?

The most common causes are: wrong port in filebeat.yml, Grok pattern mismatch causing parse failure, or wrong index pattern name in Kibana.

---

**Q: How do you prevent data loss if Logstash crashes?**

A: Set `queue.type: persisted` in logstash.yml. This enables disk-backed queuing — incoming data is written to the disk path specified in `path.data` before being processed. If Logstash crashes or restarts, it reads from the persisted queue and continues from where it left off. You also need to ensure adequate disk space on the `path.data` volume, as the queue can grow large during Elasticsearch outages.

---

**Q: What is split-brain in Elasticsearch and how do you prevent it?**

A: Split-brain occurs when a cluster divides into two independent groups that both believe they are the legitimate cluster, causing data inconsistency and corruption. You prevent it by always running an **odd number of master-eligible nodes** (minimum 3 in production) and setting `discovery.zen.minimum_master_nodes` (Elasticsearch 6.x) or relying on the automatic quorum calculation in Elasticsearch 7+ (which requires `cluster.initial_master_nodes` only at bootstrap). The quorum is `(master-eligible nodes / 2) + 1`. With 3 master-eligible nodes, quorum is 2, so one node can go down without split-brain.

---

### Performance Questions

**Q: How do you configure JVM heap size for Elasticsearch?**

A: JVM heap is configured in the `jvm.options` file, not in elasticsearch.yml. The rule of thumb is to set heap to 50% of available RAM but never exceed 31GB. Both `-Xms` (minimum) and `-Xmx` (maximum) should be set to the same value to prevent heap resizing at runtime, which causes GC pauses. For example, on a 16GB RAM server: `-Xms8g -Xmx8g`.

---

**Q: What is Index Lifecycle Management (ILM) and why is it important?**

A: ILM is Elasticsearch's built-in policy engine for managing index data over time. It automatically moves data through phases — Hot (active writes, fast SSDs), Warm (read-only, slower disks), Cold (archived, cheapest storage), and Delete (automatic cleanup). This is critical for production because log data grows continuously. Without ILM, you'll eventually run out of disk space. ILM lets you define retention policies (e.g., keep data for 30 days) and automatically enforces them.

---

### Security Questions

**Q: How do you enable TLS between Elasticsearch nodes?**

A: First, generate a CA and node certificates using `elasticsearch-certutil`. Then configure `elasticsearch.yml` with:
- `xpack.security.transport.ssl.enabled: true`
- `xpack.security.transport.ssl.keystore.path` pointing to the `.p12` certificate file
- `xpack.security.transport.ssl.truststore.path` for the CA trust store

Restart all nodes. This encrypts all inter-node communication. For HTTP (REST API) encryption, separately enable `xpack.security.http.ssl.enabled: true`.

---

**Q: What is the principle of least privilege in an ELK context?**

A: Each component should have only the permissions it needs — nothing more. Kibana uses the `kibana_system` user (not the `elastic` superuser), which has only the permissions Kibana's internal operations require. Logstash should use a dedicated user with only `write` permission to its target indexes, not admin access. Application engineers should have read-only access to their own team's indexes, not the entire cluster. This limits the blast radius if credentials are ever compromised.

---

## Quick Reference Cheat Sheet

| Check | Command |
|-------|---------|
| Cluster health | `GET /_cluster/health` |
| List all indexes | `GET /_cat/indices?v` |
| Check nodes | `GET /_cat/nodes?v` |
| View shards | `GET /_cat/shards?v` |
| Check Logstash pipeline | `curl localhost:9600/_node/stats/pipeline` |
| Check Filebeat status | `filebeat test config` / `filebeat test output` |
| View Kibana logs | `journalctl -u kibana` |
| View Elasticsearch logs | `journalctl -u elasticsearch` |

---

## Useful Documentation Links

- Elasticsearch Reference: https://www.elastic.co/guide/en/elasticsearch/reference/current/index.html
- Logstash Reference: https://www.elastic.co/guide/en/logstash/current/index.html
- Kibana Guide: https://www.elastic.co/guide/en/kibana/current/index.html
- Filebeat Reference: https://www.elastic.co/guide/en/beats/filebeat/current/index.html
- Grok Patterns: https://github.com/elastic/logstash/blob/v1.4.2/patterns/grok-patterns
- Grok Debugger (online): https://grokdebug.herokuapp.com/

---

*This guide covers ELK Stack fundamentals, configuration, real-time data flow, security, and interview preparation. For production deployments, always consult the official Elastic documentation for your specific version.*
