# Invesco Principal Engineer I — Interview Prep

## Role Summary

Cloud Infrastructure + Operations role in financial services. Focus areas:
- AWS infrastructure at scale
- Monitoring (Splunk, CloudWatch) + Incident Management (ServiceNow, ITIL)
- Security (WIZ, compliance)
- IaC (Terraform, OpenTofu)
- Leadership across 100+ teams

---

## TOP 7 SCENARIO QUESTIONS

---

### Q1: How would you design a secure multi-account AWS environment with US vs EU data residency?

**Your Answer (30 seconds):**

"I use AWS Organizations with separate OUs per region. Each OU has a Service Control Policy that blocks all API calls to regions outside its boundary. Even an account admin cannot create resources in the wrong region — SCPs override everything. On top of that, Terraform validates at plan time, CI/CD pipelines have pre-apply checks, and AWS Config detects any drift."

**The Structure:**

```
AWS Organizations
├── OU: US-Workloads    → SCP allows only us-east-1, us-west-2
│   ├── us-prod
│   ├── us-staging
│   └── us-dev
├── OU: EU-Workloads    → SCP allows only eu-west-1, eu-central-1
│   ├── eu-prod
│   ├── eu-staging
│   └── eu-dev
├── OU: Shared-Services → networking, security, logging
└── OU: Sandbox         → developer accounts (budget-limited)
```

**Why separate accounts (not just tags)?**
- Hard isolation — no IAM mistake can cross the boundary
- Network: EU VPCs cannot route to US via Transit Gateway
- Encryption: Region-specific KMS keys, non-shareable
- Audit: CloudTrail proves data never left the region

---

### Q2: How do you achieve Zero-Trust in CI/CD when connecting GitHub Actions to AWS?

**Your Answer (30 seconds):**

"No stored AWS credentials anywhere. We use OIDC federation — GitHub Actions gets a short-lived token, exchanges it with AWS via AssumeRoleWithWebIdentity, gets a 15-minute session scoped to that specific repo and environment. No secrets to rotate, no credentials to leak."

**How it works:**

```
GitHub Actions  →  OIDC Token  →  AWS IAM  →  Short-lived credentials (15 min)
                                     ↓
                              Role scoped to:
                              - This repo only
                              - This branch only
                              - This environment only
                              - Minimum permissions
```

**Key controls:**
- No long-lived AWS access keys stored in GitHub
- Each repo gets its own IAM role (not shared)
- Production role only assumable from `main` branch
- GitHub Environments require approval for prod deploys
- CloudTrail logs every assume-role with repo/branch/actor

---

### Q3: How do you maintain standards across 100+ teams without becoming a bottleneck?

**Your Answer (30 seconds):**

"Instead of making teams raise tickets and wait for my team to provision things, I give them ready-made building blocks. They use our Terraform modules, our CI/CD templates — all the security and compliance rules are already built into those blocks. Teams deploy on their own. My team only gets involved for exceptions."

**Simple Explanation (think of it like a restaurant):**

```
OLD WAY (Bottleneck):
  100 teams → raise ticket → wait for platform team → platform team provisions → done
  Problem: Platform team becomes the queue. Everyone waits.

NEW WAY (Self-Service with Guardrails):
  100 teams → pick from menu of approved modules → deploy themselves → automated checks ensure compliance
  Problem solved: Nobody waits. Standards are enforced automatically.
```

**What are these "building blocks"?**

| Building Block | What it does | Example |
|---------------|-------------|---------|
| **Terraform modules** | Pre-built infrastructure templates with security baked in | Team says "I need a database" → uses the module → gets encrypted RDS with backups automatically |
| **CI/CD templates** | Shared pipeline that already has security scanning, testing, approval | Team adds 1 line to use it → gets full pipeline with all checks |
| **Policy-as-code** | Automated rules that reject bad configurations | Team tries to create public S3 bucket → pipeline auto-rejects with clear error message |
| **Golden images** | Pre-hardened container base images | Team builds on top → inherits all security patches automatically |

**How compliance is enforced (without humans blocking):**

```
Developer writes code
    ↓
Pushes to GitHub
    ↓
CI pipeline runs automatically:
  ✓ Uses shared template (standards built in)
  ✓ Security scan passes (Wiz/Trivy)
  ✓ Policy check passes (OPA validates Terraform)
  ✓ Deploys to production
    ↓
No ticket. No wait. No bottleneck.
```

**If something violates a rule:**
- Pipeline fails immediately with a clear message
- Developer fixes it themselves
- No human reviewer needed for standard cases

**The key idea:** Don't make teams ask permission to do things the right way. Make the right way the default, and only block them when they try to do something dangerous.

---

### Q4: Walk through handling a Major Production Outage with 99.99% SLA.

**Your Answer (30 seconds):**

"99.99% means max 52 minutes downtime per year. My first action: check if anything deployed recently — if yes, rollback immediately, investigate later. If not, I open a war room, run parallel investigation streams, and communicate every 15 minutes."

**Timeline:**

| Minute | Action |
|--------|--------|
| 0-2 | Alert fires → On-call acknowledges |
| 2-5 | Classify severity → Open war room → Page SMEs |
| 5-15 | **Parallel investigation:** recent deploys? infra metrics? dependency health? error logs? |
| 15-30 | **Mitigate:** Rollback / Scale up / Failover (fix now, RCA later) |
| 30+ | Verify recovery → Stand down → Status page "Resolved" |
| 48 hrs | Blameless post-mortem → Action items in Jira |

**Decision rules:**
- Recent deploy + issues = **rollback first, ask questions later**
- Unknown cause = **escalate early**, don't spend 30 min alone
- Multiple services down = **fix the shared dependency**, not the symptoms

**How to stay at 99.99%:**
- Multi-AZ everything, no single points of failure
- Canary deployments catch issues with 1% traffic
- Pre-written runbooks for known failure modes
- Automated failover (Route53 health checks, RDS Multi-AZ)

---

### Q5: How do you use Wiz (CSPM) to secure runtime environments?

**Your Answer (30 seconds):**

"Wiz scans our entire cloud agentlessly — VMs, containers, serverless, databases — and builds a security graph. Instead of saying 'you have 10,000 CVEs,' it says 'these 3 CVEs are actually exploitable from the internet and can reach your database.' That prioritization is what lets a small team secure hundreds of accounts."

**Three use cases:**

**1. Shift-Left (CI/CD):**
- Scan container images in pipeline
- Block deployment if critical exploitable CVE found
- Developer fixes before code reaches production

**2. Runtime Detection:**
- Continuously scans running workloads for new CVEs
- Identifies toxic combinations: critical CVE + runs as root + network access to DB
- Alerts create ServiceNow incidents automatically

**3. Compliance Evidence:**
- Maps findings to SOC2/CIS/PCI frameworks
- Generates audit-ready reports automatically
- Auditors get Wiz dashboard instead of manual screenshots

**Why Wiz over traditional scanners:**
- Agentless = no performance impact on production
- Attack path analysis = prioritization by actual risk, not just CVSS score
- Covers everything (VMs, containers, serverless, data stores) in one tool

---

### Q6: How would you migrate hundreds of Jenkins pipelines to GitHub Actions?

**Your Answer (30 seconds):**

"Never big-bang. I categorize pipelines by complexity, build reusable GitHub Actions templates for common patterns, then migrate in waves starting with non-critical services. Both systems run in parallel during transition."

**The plan:**

```
Phase 1 (Week 1-2):  DISCOVER
  → Inventory all pipelines via Jenkins API
  → Categorize: Simple (70%) | Complex (20%) | Exotic (10%)
  → Map Jenkins plugins to GitHub Actions equivalents

Phase 2 (Week 2-4):  BUILD TEMPLATES
  → Create reusable workflows: build, test, scan, deploy
  → Set up OIDC auth (no stored credentials)
  → Write migration guide for teams

Phase 3 (Month 1-3): MIGRATE IN WAVES
  → Wave 1: Non-critical/dev pipelines (platform team does it)
  → Wave 2: Standard prod pipelines (teams do it with support)
  → Wave 3: Complex pipelines (pair with platform team)

Phase 4 (Month 4):   DECOMMISSION
  → Jenkins read-only (no new pipelines)
  → Archive and shut down
```

**Key decisions:**
- Jenkins shared libraries → GitHub reusable workflows
- Jenkins credentials → OIDC for AWS, GitHub secrets for others
- Approval gates → GitHub Environments with required reviewers
- Self-hosted runners for private VPC access

---

### Q7: How do you handle a team that refuses your security guardrails because it slows them down?

**Your Answer (30 seconds):**

"First I listen and measure the actual impact. Then I optimize the guardrail — make it faster, not remove it. If a security scan takes 8 minutes, I restructure it to take 45 seconds. When the compliant path is fast, resistance disappears."

**My 4-step approach:**

**Step 1: Listen & Measure**
- What specifically is slow? A 10-min scan? An approval gate? A flaky check?
- Measure actual time impact — often less than perceived

**Step 2: Optimize (Not Remove)**

| Complaint | Fix |
|-----------|-----|
| "Scan takes 10 min" | Run in parallel, scan only changed files, cache results |
| "Approval gate delays 2 hours" | Auto-approve for non-prod, pre-approved paths for standard changes |
| "Policy keeps failing" | Better error messages, pre-commit hooks catch issues locally |

**Step 3: Show the Risk**
- Share real incidents: "This CVE took down a trading platform for 4 hours. Our scan catches it in 30 seconds."
- In financial services, the cost of a breach far outweighs 45 seconds of scan time

**Step 4: Escalate Only as Last Resort**
- Present data to their manager: "Here's the compliance gap we're accepting"
- In regulated industries, this is rarely needed — the risk is clear

**Key principle:** "Security should be invisible when you're doing the right thing, and only visible when you're about to do something dangerous."

---

## ADDITIONAL QUESTIONS (By JD Category)

---

### Infrastructure Management

**Q: "Walk me through a scalable AWS infrastructure you've designed."**

"Multi-account setup with Organizations. VPC with 3 AZs — private subnets for workloads, public only for ALB. EKS for microservices with managed node groups and autoscaling. RDS Multi-AZ for databases. Terraform modules for everything — teams consume from a private registry."

---

### Monitoring & Alerting (Splunk + CloudWatch + ServiceNow)

**Q: "How do you implement monitoring?"**

"Three layers:
- **CloudWatch** — AWS-native metrics (EC2, RDS, EKS). Custom metrics via agent for app-level data.
- **Splunk** — Centralized logs. All app logs, VPC flow logs, CloudTrail ship via Kinesis Firehose. Dashboards + correlation rules for anomaly detection.
- **ServiceNow** — Alerts auto-create incidents with proper severity, assignment group, and initial diagnostics. SLA tracking built in."

**Q: "How do you reduce alert fatigue?"**

"Three rules: (1) Tune thresholds from historical data, not guesses. (2) Correlate related alerts into single incidents. (3) If nobody acts on it, it's not an alert — remove it. Monthly review of alert volumes."

---

### Automation (Terraform + Python + Bash)

**Q: "How do you manage Terraform at scale?"**

"Reusable modules in a private registry, versioned. State in S3 + DynamoDB locking, one state per environment per component. OPA/Sentinel policies in CI — blocks non-compliant resources before apply. Nightly drift detection via scheduled `terraform plan`."

**Q: "Give an example of automation you've built."**

"Automated incident triage — Python script that on P1 alert: queries CloudWatch metrics, checks recent deployments via ArgoCD API, collects Splunk logs, and creates a ServiceNow incident with pre-populated diagnostics. Reduced initial triage from 15 minutes to 2 minutes."

---

### Security & Compliance

**Q: "What is WIZ and how have you used it?"**

"Agentless CSPM that scans entire cloud estate for vulnerabilities, misconfigs, and attack paths. I use it for: CI/CD blocking (fail deploys with critical CVEs), runtime detection (continuous scanning), and compliance evidence (auto-generated SOC2/CIS reports for auditors)."

**Q: "How do you enforce security?"**

"Defense in depth: SCPs prevent (region restrictions, service restrictions). WIZ detects (runtime scanning). OPA blocks (policy-as-code in CI). AWS Config monitors (drift detection + auto-remediation). CloudTrail audits (who did what, when)."

---

### Cost Optimization

**Q: "How do you optimize a multi-million dollar AWS bill?"**

"Four pillars:
1. **Visibility** — Mandatory tagging, per-team dashboards, anomaly alerts
2. **Right-sizing** — Compute Optimizer + CloudWatch metrics → downsize over-provisioned resources (20-30% savings)
3. **Pricing** — Savings Plans for baseline, Spot for batch/CI, Graviton for 20% cheaper compute
4. **Architecture** — VPC endpoints (no NAT charges), S3 Intelligent-Tiering, dev environments auto-shutdown after hours

Typical result: 40-50% reduction in year 1 on an over-provisioned account."

---

### Monolith → Microservices

**Q: "How do you decouple legacy monoliths safely?"**

"Strangler Fig pattern — never a big-bang rewrite. Extract one service at a time, starting with the least-coupled. API Gateway routes traffic between monolith and new microservice. Run both in parallel until confident. The hardest part is splitting the shared database — I use Change Data Capture (DMS/Debezium) during transition to keep data in sync."

---

### Networking

**Q: "How do you troubleshoot network issues in AWS?"**

"Systematic: (1) Security Groups — inbound/outbound rules. (2) NACLs — subnet-level deny rules. (3) Route tables — does route exist? (4) VPC Flow Logs — traffic ACCEPTED or REJECTED? (5) DNS — can the service resolve? (6) For cross-account: Transit Gateway routes."

---

## TOOLS THEY MENTION — Quick Responses

| Tool | What You Say |
|------|-------------|
| **Splunk** | "Centralized logs, dashboards, correlation searches, alert actions to ServiceNow" |
| **CloudWatch** | "Native AWS metrics, custom metrics, alarms, log insights, anomaly detection" |
| **ServiceNow** | "ITSM: incidents, change management, CMDB, SLA tracking, problem management" |
| **WIZ** | "Agentless CSPM, attack path analysis, CI/CD scanning, compliance evidence" |
| **Terraform/OpenTofu** | "IaC modules, state management, policy-as-code, drift detection" |
| **ITIL** | "Incident → Problem → Change management processes, CAB for prod changes" |
| **Jenkins** | "CI/CD pipelines, shared libraries, agent management" |
| **Docker/Kubernetes** | "Containerization, EKS, deployments, HPA, troubleshooting" |

---

## QUESTIONS YOU ASK THEM

1. "What does your current AWS footprint look like — single account, multi-account?"
2. "How mature is IaC adoption — Terraform everywhere, or still some manual provisioning?"
3. "What's the on-call rotation structure?"
4. "What's the biggest operational challenge the team faces today?"
5. "Are you migrating to containers, or primarily EC2-based?"
6. "How does change management work — full ITIL CAB, or lighter process?"

---

## ANSWER STRUCTURE (Use This for Every Question)

```
1. State approach (1 sentence — what you do)
2. Why (trade-offs, why this over alternatives)
3. Example (concrete — from your experience)
4. Outcome (metric or result)
```

Example: "We use Strangler Fig for decomposition [approach] because big-bang rewrites fail in financial services [why]. We extracted notifications first — lowest risk [example]. Zero downtime, latency dropped from 2s to 200ms [outcome]."
