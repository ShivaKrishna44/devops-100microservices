# Deployment Flow — How Everything Connects

## The Full Picture (End to End)

```
Developer pushes code to Git
    ↓
CI Pipeline builds Docker image → pushes to ECR → updates image tag in values.yaml
    ↓
ArgoCD detects Git change (new image tag)
    ↓
ArgoCD renders Helm chart (templates + values = Kubernetes YAML)
    ↓
Kubernetes applies: Deployment, Service, HPA created/updated
    ↓
Pods start running with new image
```

---

## When Does Each File Execute?

### Step 1: CI Pipeline (runs on code push)

| File | What Happens |
|------|-------------|
| `.github/workflows/ci.yml` | Builds Docker image, pushes to ECR, updates image tag in values file |

**Trigger:** Developer pushes to `main` branch
**Output:** New image in ECR + updated `values-order-service.yaml` with new tag

---

### Step 2: ArgoCD App Definition (applied once)

| File | What Happens |
|------|-------------|
| `kubernetes/argocd/apps/order-service.yaml` | Tells ArgoCD: "Watch this chart in Git, deploy to this namespace" |
| `kubernetes/argocd/apps/payment-service.yaml` | Same — one per service |
| `kubernetes/argocd/apps/user-service.yaml` | Same — one per service |

**When applied:** Once, when setting up the project. ArgoCD then watches Git forever.

**What it says:**
```yaml
spec:
  source:
    repoURL: https://github.com/your-org/devops-100microservices.git
    path: charts/microservice          ← "use this Helm chart"
    helm:
      valueFiles:
        - values.yaml                   ← "base defaults"
        - values-order-service.yaml     ← "this service's config"
  destination:
    namespace: production               ← "deploy here"
  syncPolicy:
    automated:
      selfHeal: true                    ← "auto-fix manual changes"
```

---

### Step 3: Helm Chart (rendered every deploy)

| File | What It Produces |
|------|-----------------|
| `charts/microservice/templates/deployment.yaml` | → Kubernetes Deployment (pods) |
| `charts/microservice/templates/service.yaml` | → Kubernetes Service (networking) |
| `charts/microservice/templates/hpa.yaml` | → HorizontalPodAutoscaler |
| `charts/microservice/templates/servicemonitor.yaml` | → Prometheus scrape config |

**How Helm works:**
```
Template (deployment.yaml)     +    Values (values-order-service.yaml)    =    Final YAML
image: "{{ .Values.image }}"        image: 589389.ecr/order-service:abc123      image: 589389.ecr/order-service:abc123
replicas: {{ .Values.replicas }}    replicas: 3                                  replicas: 3
```

---

### Step 4: Values Files (config per service)

| File | Purpose |
|------|---------|
| `charts/microservice/values.yaml` | Default values (shared by all services) |
| `charts/microservice/values-order-service.yaml` | Order service specific: image, replicas, env vars |
| `charts/microservice/values-payment-service.yaml` | Payment service specific |
| `charts/microservice/values-user-service.yaml` | User service specific |

**CI pipeline updates the image tag here:**
```yaml
# values-order-service.yaml (before CI)
image:
  repository: 589389425618.dkr.ecr.us-east-1.amazonaws.com/order-service
  tag: "abc123"   ← CI changes this to new commit SHA

# After CI runs:
  tag: "def456"   ← new tag triggers ArgoCD sync
```

---

### Step 5: Other Kubernetes Manifests (applied separately)

| File | When Applied | How |
|------|-------------|-----|
| `kubernetes/pdb/pdb-services.yaml` | Once (manual) | `kubectl apply -f` |
| `kubernetes/monitoring/prometheus-values.yaml` | Once (Helm install) | Used by monitoring script |
| `kubernetes/monitoring/alertmanager-config.yaml` | Once (manual) | `kubectl apply -f` |

These are NOT managed by ArgoCD in our setup — they're platform-level configs applied by the platform team.

---

## Visual Timeline

```
TIME →

Code Push     CI Builds      CI Updates      ArgoCD         Helm          Kubernetes
  |           Image          Values File     Detects        Renders       Applies
  |             |               |            Change         Templates     Resources
  v             v               v              v               v             v
[push]  →  [docker build] → [sed tag] →  [sync] →  [template+values] → [Deployment]
            [push ECR]      [git push]                                    [Service]
                                                                          [HPA]
                                                                          [Pods Running]

Total time: ~3-5 minutes from push to pods running
```

---

## Simple Rules

1. **ArgoCD App YAML** = applied once, tells ArgoCD what to watch
2. **Helm templates** = reusable blueprints, same chart for all services
3. **Values files** = per-service config (image, replicas, env)
4. **CI pipeline** = only changes the image tag in values file
5. **ArgoCD** = detects the change, renders chart, applies to cluster

---

## Interview Answer

> "Our deployment flow is: CI pipeline builds the image, pushes to ECR, and updates the image tag in the Helm values file. ArgoCD watches Git, detects the tag change within 3 minutes, renders the Helm chart with the new values, and applies the resulting manifests to the cluster. It's fully automated — developer pushes code, 5 minutes later it's running in production. ArgoCD self-heal ensures no manual drift persists."

---

## In Production — What's Different

| Lab (what we did) | Production (what you say in interviews) |
|---|---|
| `kubectl create deployment` | ArgoCD syncs from Git |
| `kubectl expose` | Service defined in Helm chart |
| `kubectl set image` | CI updates values file → ArgoCD syncs |
| Manual `kubectl apply` for PDBs | Everything in Git, managed by ArgoCD |
| No approval gate | PR review + environment approval before prod |
