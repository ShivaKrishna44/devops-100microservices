# Invesco Principal Engineer I — Interview Prep

## Role Analysis

This is a **Cloud Infrastructure + Operations** role (not pure DevOps/SRE). Key signals:
- Splunk + CloudWatch + ServiceNow = operations-heavy
- ITIL + Major Incidents = process-oriented
- WIZ = cloud security posture management
- OpenTofu mention = they're forward-thinking on IaC
- AI mentioned in infra = likely ML workloads or AI-assisted ops

---

## Top Questions They Will Ask (Mapped to JD)

---

### 1. INFRASTRUCTURE MANAGEMENT

**Q: "Walk me through how you've designed a scalable cloud infrastructure on AWS."**

> "In my current role, I architected a multi-account AWS setup using Organizations with separate OUs for production, staging, and shared services. The core infrastructure runs on EKS with 3 AZs for HA, using Terraform modules for VPC, EKS, RDS, and ElastiCache. I designed the VPC with private subnets for workloads, public subnets only for ALB/NLB, and NAT Gateways per AZ for redundancy. For compute, we use a mix of EC2 (for stateful workloads) and EKS managed node groups (for microservices) with autoscaling based on CPU and custom metrics."

**Q: "How do you handle multi-AZ / multi-region HA?"**

> "For our critical services, we run active-active across 3 AZs within a region. RDS uses Multi-AZ with automatic failover. For DR, we have a pilot-light setup in a secondary region — RDS read replicas promote to primary, EKS cluster stays warm with minimum nodes, Route53 health checks trigger failover. RTO is under 15 minutes, RPO under 1 minute for critical data."

**Q: "How do you handle AI/ML infrastructure on AWS?"**

> "We provision SageMaker endpoints for model inference, use S3 for training data with lifecycle policies, and EKS with GPU node groups (p3/g4 instances) for custom training jobs. For cost control, we use Spot instances for training and reserved capacity for inference endpoints."

---

### 2. MONITORING & ALERTING (Splunk + CloudWatch + ServiceNow)

**Q: "How do you implement monitoring and alerting in your environment?"**

> "We use a layered approach:
> - **CloudWatch** for AWS-native metrics (EC2, RDS, EKS control plane, Lambda). Custom metrics pushed via CloudWatch agent for application-level data.
> - **Splunk** for centralized log aggregation and analysis. All application logs, VPC flow logs, CloudTrail audit logs ship to Splunk via Kinesis Firehose. We build dashboards and saved searches for proactive anomaly detection.
> - **ServiceNow** integration for incident management — alerts from CloudWatch/Splunk trigger ServiceNow incidents automatically based on severity. P1/P2 alerts go to PagerDuty first, then auto-create ServiceNow tickets for tracking and SLA compliance."

**Q: "How do you reduce alert fatigue?"**

> "Three things: First, I tune thresholds based on historical data — not arbitrary numbers. Second, I implement correlation rules in Splunk to group related alerts into a single incident. Third, I categorize alerts by actionability — if no one needs to act, it's a notification, not an alert. We review alert volumes monthly and silence or tune anything with less than 10% action rate."

**Q: "How do you integrate monitoring with ServiceNow?"**

> "CloudWatch alarms trigger SNS → Lambda → ServiceNow API to create incidents with proper categorization, assignment group, and priority. Splunk alerts use webhook actions to the ServiceNow REST API. Every incident auto-populates with affected CI (Configuration Item), environment, and initial diagnostics. Resolution notes feed back via the same integration for knowledge base updates."

---

### 3. AUTOMATION (Terraform + CloudFormation + OpenTofu + Python + Bash)

**Q: "How do you manage IaC at scale with Terraform?"**

> "We structure Terraform as reusable modules in a private registry — VPC, EKS, RDS, S3 modules that teams consume with versioned references. State is stored in S3 with DynamoDB locking, one state file per environment per component. We enforce standards via Sentinel/OPA policies that run in CI before apply — no public S3 buckets, no open security groups, mandatory tagging. For drift detection, we run `terraform plan` nightly and alert on unexpected changes."

**Q: "Why would you consider OpenTofu over Terraform?"**

> "OpenTofu is the open-source fork after HashiCorp's BSL license change. For an enterprise like Invesco, the decision depends on: licensing concerns with Terraform Enterprise, community module compatibility, and long-term support. Both are syntactically compatible today. If the organization wants to avoid vendor lock-in on the IaC tool itself, OpenTofu is the risk-free choice. I'd evaluate based on the enterprise support model and existing Terraform Enterprise investment."

**Q: "Give an example of automation you've built with Python/Bash."**

> "I automated our incident response runbooks — a Python-based tool that on P1 alert: (1) queries CloudWatch for the affected resource metrics, (2) checks recent deployments via the ArgoCD API, (3) collects relevant Splunk logs, (4) packages it all into a ServiceNow incident with pre-populated diagnostics. Reduced initial triage time from 15 minutes to under 2 minutes."

---

### 4. INCIDENT RESPONSE & MAJOR INCIDENTS

**Q: "Walk me through how you handle a Major Incident."**

> "We follow ITIL's Major Incident process:
> 1. **Detection** — Automated alert from Splunk/CloudWatch or user report
> 2. **Triage** — On-call engineer assesses impact and severity (P1-P4)
> 3. **Bridge call** — For P1/P2, I open a war room (Teams/Zoom bridge), page relevant SMEs
> 4. **Communicate** — Status page update, stakeholder email within 15 minutes
> 5. **Resolve** — Parallel workstreams: identify root cause + implement workaround
> 6. **Post-mortem** — Blameless RCA within 48 hours, action items tracked in Jira
>
> As Principal, my role is usually Incident Commander — coordinating teams, making escalation decisions, and ensuring communication flows."

**Q: "Tell me about a critical production incident you resolved."**

> "We had an intermittent 5xx spike on our payment processing service during peak hours. Initial investigation showed healthy pods and normal CPU/memory. I checked Splunk logs and found connection timeout errors to our RDS instance. CloudWatch showed DB connections at 100% of max. Root cause: a code change introduced connection leaks — connections weren't being returned to the pool. Immediate fix: scaled RDS connection limit and restarted the affected pods. Long-term: added connection pool monitoring, implemented connection timeout enforcement, and added a pre-deploy load test that catches connection leaks."

---

### 5. SECURITY & COMPLIANCE (WIZ mentioned)

**Q: "How do you enforce security in your cloud environment?"**

> "Defense in depth:
> - **Preventive**: SCPs restrict regions/services, IAM follows least-privilege with permission boundaries, no long-lived credentials (use IRSA/IAM roles everywhere)
> - **Detective**: WIZ for cloud security posture management — scans for misconfigurations, vulnerabilities, and lateral movement paths. GuardDuty for threat detection, CloudTrail for audit.
> - **Responsive**: Automated remediation via Lambda — if WIZ finds a public S3 bucket, it auto-blocks public access and creates a ServiceNow incident.
> - **Compliance**: AWS Config rules for continuous compliance checking against CIS benchmarks, SOC2 controls mapped and evidenced automatically."

**Q: "What is WIZ and how have you used it?"**

> "WIZ is an agentless cloud security platform that scans your entire cloud estate — VMs, containers, serverless, data stores — for vulnerabilities, misconfigurations, and toxic risk combinations. I use it for: vulnerability prioritization (it shows which CVEs are actually exploitable given your network context), compliance dashboards for audit evidence, and CI/CD integration to block deployments with critical findings. The agentless approach is key — no performance impact on production workloads."

---

### 6. PERFORMANCE & COST OPTIMIZATION

**Q: "How do you optimize cloud costs?"**

> "I approach it in layers:
> - **Right-sizing**: Use CloudWatch metrics + AWS Compute Optimizer recommendations. If a t3.large consistently uses 10% CPU, downsize it.
> - **Reserved/Savings Plans**: For stable workloads (RDS, baseline EKS nodes), commit to 1-year savings plans — typically 30-40% savings.
> - **Spot instances**: For non-critical batch jobs, CI/CD runners, and dev environments.
> - **Automation**: Lambda functions to stop dev environments after hours, lifecycle policies on S3/EBS snapshots.
> - **Tagging + Showback**: Every resource tagged with team/project/cost-center. Monthly cost reports per team with anomaly alerts."

---

### 7. COLLABORATION & LEADERSHIP (Principal Level)

**Q: "How do you drive standards across teams?"**

> "I create 'golden paths' — pre-built Terraform modules, CI/CD templates, and reference architectures that make the right way the easy way. I don't mandate through policy alone — I show teams the value. For example, I built a self-service platform where teams can deploy new services by filling out a YAML config, and the pipeline handles everything else. Adoption went from forced compliance to organic demand."

**Q: "How do you mentor less experienced engineers?"**

> "I pair on incident response — nothing teaches faster than real problems. I document decisions in ADRs (Architecture Decision Records) so juniors understand the 'why'. I run weekly office hours where anyone can bring infrastructure questions. And I delegate progressively — start with guided tasks, move to design reviews, then full ownership."

---

### 8. NETWORKING

**Q: "Explain your VPC architecture."**

> "3-tier: public subnets (ALB/NLB only), private subnets (applications/EKS), isolated subnets (databases). NAT Gateway per AZ for HA. VPC peering or Transit Gateway for cross-account communication. Security groups as primary firewall — stateful, least-privilege, no 0.0.0.0/0 ingress. NACLs as secondary defense for subnet-level rules. Route53 private hosted zones for internal service discovery."

**Q: "How do you troubleshoot network connectivity issues in AWS?"**

> "Systematic approach: (1) Security Groups — verify inbound/outbound rules, (2) NACLs — check if deny rules are blocking, (3) Route tables — ensure routes exist to target, (4) VPC Flow Logs — check if traffic is ACCEPTED or REJECTED, (5) DNS — verify resolution with `nslookup`, (6) For cross-account: check Transit Gateway routes and VPC peering configurations."

---

## Tools They Mention — Be Ready to Discuss

| Tool | Your Response |
|------|--------------|
| **Splunk** | Log aggregation, dashboards, alerts, correlation searches, saved searches |
| **CloudWatch** | Native AWS metrics, custom metrics, alarms, log groups, Insights queries |
| **ServiceNow** | ITSM — incidents, change management, CMDB, SLA tracking |
| **WIZ** | Agentless cloud security scanning, vulnerability prioritization, compliance |
| **Terraform/OpenTofu** | IaC, modules, state management, Sentinel policies, drift detection |
| **Jenkins** | CI/CD pipelines, shared libraries, agent management |
| **Docker/Kubernetes** | Containerization, EKS, deployments, troubleshooting |
| **ITIL** | Incident, Problem, Change Management processes |
| **Jira/Confluence** | Sprint planning, documentation, runbooks |

---

## Questions YOU Should Ask Them

1. "What does the current cloud footprint look like — single account, multi-account, multi-region?"
2. "How mature is the IaC adoption — are most teams using Terraform, or is there still manual provisioning?"
3. "What's the on-call rotation structure for this role?"
4. "Are you migrating workloads to containers/EKS, or is it mostly EC2-based?"
5. "What's the biggest operational challenge the team faces today?"
6. "How does the team handle change management — full ITIL CAB process, or lighter-weight?"
