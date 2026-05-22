# GitHub Setup Guide

A step-by-step guide to publishing this project to GitHub so it's portfolio-ready.

---

## Step 1 — Create the GitHub Repository

1. Go to [github.com](https://github.com) → **New Repository**
2. Name: `elk-stack-production-project`
3. Description: `Production-level ELK Stack — log ingestion, dashboards, alerting, TLS security, Terraform IaC on AWS`
4. Set to **Public** (so recruiters can see it)
5. **Do NOT** initialize with README (we have one already)
6. Click **Create Repository**

---

## Step 2 — Push from Your Local Machine

```bash
# Navigate to project folder
cd elk-stack-project/

# Initialize git
git init

# Add all files
git add .

# First commit
git commit -m "feat: initial ELK stack project structure with all 5 phases"

# Link to GitHub
git remote add origin https://github.com/YOUR_USERNAME/elk-stack-production-project.git

# Push
git branch -M main
git push -u origin main
```

---

## Step 3 — Commit After Each Phase

Use conventional commits — this shows professional Git hygiene to reviewers.

```bash
# After completing Phase 1
git add phase-1-infrastructure/
git commit -m "feat(phase-1): add Docker Compose and Terraform EC2 provisioning"
git push

# After completing Phase 2
git add phase-2-log-ingestion/
git commit -m "feat(phase-2): add Logstash multi-pipeline with Grok filters for nginx, app, syslog"
git push

# After completing Phase 3
git add phase-3-kibana-dashboards/
git commit -m "feat(phase-3): add Kibana dashboard configs and KQL reference"
git push

# After completing Phase 4
git add phase-4-alerting/
git commit -m "feat(phase-4): add ElastAlert2 rules for error rate, SSH brute force, response time"
git push

# After completing Phase 5
git add phase-5-hardening/
git add configs/
git commit -m "feat(phase-5): add X-Pack TLS, RBAC roles, ILM policy, hardened Terraform"
git push
```

---

## Step 4 — Add Screenshots to README

After building each dashboard, take screenshots and add them to the README for visual impact.

```bash
# Create a screenshots folder
mkdir -p screenshots

# After screenshotting, add to git
git add screenshots/
git commit -m "docs: add Kibana dashboard screenshots for portfolio"
git push
```

Update `README.md` to include screenshots:
```markdown
## 📸 Screenshots

### Nginx Analytics Dashboard
![Nginx Dashboard](./screenshots/nginx-analytics-dashboard.png)

### Application Performance Dashboard
![App Performance](./screenshots/app-performance-dashboard.png)

### Security Events Dashboard
![Security Events](./screenshots/security-events-dashboard.png)

### ElastAlert2 Slack Notification
![Slack Alert](./screenshots/elastalert2-slack-notification.png)
```

---

## Step 5 — Add GitHub Actions CI (Bonus)

Add a workflow to validate Terraform and Logstash configs on every push.

**`.github/workflows/validate.yml`**
```yaml
name: Validate Configs

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  validate-terraform:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.6.0

      - name: Terraform Format Check
        run: terraform fmt -check -recursive
        working-directory: ./phase-1-infrastructure/terraform

      - name: Terraform Init
        run: terraform init -backend=false
        working-directory: ./phase-1-infrastructure/terraform

      - name: Terraform Validate
        run: terraform validate
        working-directory: ./phase-1-infrastructure/terraform

  validate-yaml:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install yamllint
        run: pip install yamllint

      - name: Lint YAML configs
        run: yamllint phase-4-alerting/elastalert2/rules/

  lint-docker-compose:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Validate docker-compose.yml
        run: docker compose config
```

---

## Step 6 — Write a Good GitHub Profile README Section

Add this to your GitHub Profile README or the repo description:

```
🔍 What's in this repo:
• 5-phase project building a production ELK Stack on AWS
• Logstash multi-pipeline with Grok patterns for Nginx, App JSON, Syslog
• ElastAlert2 rules: spike detection, SSH brute-force, error-rate threshold
• Kibana dashboards: error rates, P95 response time, geo maps, security events
• X-Pack TLS + RBAC + ILM policies
• Full Terraform IaC: EC2, VPC, Security Groups, remote state on S3
• Docker Compose for local and production deployment
```

---

## Recommended Repository Structure on GitHub

```
elk-stack-production-project/
├── README.md                 ← Project overview + architecture diagram
├── .gitignore
├── docker-compose.yml        ← Main stack compose file
├── configs/                  ← ES / Kibana / Logstash base configs
├── screenshots/              ← Dashboard screenshots (portfolio)
├── phase-1-infrastructure/   ← Terraform + setup guide
├── phase-2-log-ingestion/    ← Filebeat + Logstash pipelines
├── phase-3-kibana-dashboards/← Dashboard ndjson + KQL reference
├── phase-4-alerting/         ← ElastAlert2 rules + Watcher
└── phase-5-hardening/        ← TLS, RBAC, ILM, hardened Terraform
```

---

## ✅ GitHub Setup Checklist

- [ ] Repository created on GitHub as **Public**
- [ ] `.gitignore` committed (no `.env`, no `.pem`, no `*.key`)
- [ ] Initial commit pushed with all phase folders
- [ ] Separate commits for each phase (shows progression)
- [ ] Screenshots folder with Kibana dashboard screenshots
- [ ] Repository description and topics set (`elasticsearch`, `kibana`, `logstash`, `devops`, `aws`, `terraform`)
- [ ] GitHub Actions workflow added for Terraform validation
- [ ] README has architecture diagram visible on GitHub
