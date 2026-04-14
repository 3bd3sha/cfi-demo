# CI/CD Pipeline Documentation

## Overview

This repository contains two GitHub Actions pipelines:

1. **`deploy-trading-api.yml`** - Full production pipeline with monitoring
2. **`simple-pipeline.yml`** - Simplified version for learning/demos

## Pipeline Architecture

```
┌─────────────┐
│  Git Push   │
└──────┬──────┘
       │
       ▼
┌─────────────────────────────────────────────────────────┐
│              GITHUB ACTIONS WORKFLOW                     │
└─────────────────────────────────────────────────────────┘
       │
       ├──▶ Stage 1: Build & Test
       │    ├─ Checkout code
       │    ├─ Run linting
       │    ├─ Run unit tests
       │    ├─ Run integration tests
       │    ├─ Build Docker image
       │    └─ Push to registry
       │
       ├──▶ Stage 2: Deploy to Staging (if develop branch)
       │    ├─ Deploy to staging K8s
       │    ├─ Run smoke tests
       │    └─ Notify team
       │
       ├──▶ Stage 3: Deploy Canary (if main branch)
       │    ├─ Deploy to 10% of production
       │    ├─ Label pods with version="canary"
       │    └─ Create Grafana annotation
       │
       ├──▶ Stage 4: Monitor Canary ⭐ CRITICAL
       │    ├─ Query Prometheus every 30s for 10 min
       │    ├─ Compare canary vs stable metrics:
       │    │  • Error rate (fail if canary > 2x stable)
       │    │  • Latency P95 (fail if canary > 1.5x stable)
       │    │  • Order success (fail if < 99.99%)
       │    │  • Pod health (fail if any unhealthy)
       │    ├─ Auto-rollback if ANY check fails
       │    └─ Notify team of result
       │
       └──▶ Stage 5: Promote to Production (if monitoring passed)
            ├─ Scale to 50% → monitor 5 min
            ├─ Scale to 100% → monitor 5 min
            ├─ Finalize deployment
            ├─ Create Grafana annotation
            └─ Notify team

```

## Key Features

### 🔄 Continuous Integration

```yaml
on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]
```

**Triggers:**
- Push to `main` → Full production deployment
- Push to `develop` → Staging deployment
- Pull request → Build & test only

### 🧪 Automated Testing

```yaml
- Run linting (code quality)
- Run unit tests (individual functions)
- Run integration tests (API endpoints)
- Run smoke tests (health, metrics, basic operations)
- Security scanning (vulnerability detection)
```

### 🚀 Canary Deployment

**Why canary?**
- Test new version with 10% of traffic first
- Catch issues before they affect all customers
- Auto-rollback if problems detected

**Flow:**
```
10% traffic → Monitor 10 min → 50% traffic → Monitor 5 min → 100% traffic
    ↓              ↓               ↓              ↓             ↓
 Deploy        Health OK?      Scale up       Health OK?    Finalize
              ↓       ↓                      ↓       ↓
            Pass   Fail                   Pass   Fail
                     ↓                             ↓
                 ROLLBACK                      ROLLBACK
```

### 📊 Monitoring Integration

**What we monitor:**

```yaml
# Error Rate Check
Canary errors vs Stable errors
Threshold: Fail if canary > 2x stable

# Latency Check  
Canary P95 vs Stable P95
Threshold: Fail if canary > 1.5x stable

# Success Rate Check
Order execution success rate
Threshold: Fail if < 99.99% (CFI SLO)

# Pod Health Check
All canary pods must be Running
Threshold: Fail if any pod unhealthy
```

**PromQL queries used:**

```promql
# Error rate
sum(rate(http_requests_total{version="canary",status=~"5.."}[5m])) /
sum(rate(http_requests_total{version="canary"}[5m]))

# Latency P95
histogram_quantile(0.95, 
  rate(http_request_duration_seconds_bucket{version="canary"}[5m]))

# Order success rate
(sum(rate(orders_total{version="canary",status="success"}[5m])) /
 sum(rate(orders_total{version="canary"}[5m]))) * 100
```

### ⏮️ Auto-Rollback

**When rollback happens:**
- ❌ Canary error rate > 2x stable
- ❌ Canary latency > 1.5x stable
- ❌ Order success rate < 99.99%
- ❌ Any canary pod unhealthy

**Rollback process:**
```bash
kubectl rollout undo deployment/trading-api-canary
kubectl scale deployment/trading-api-canary --replicas=0
# Send alert to team
# Create Grafana annotation
```

**Impact:**
- Total customer exposure: 3-10 minutes at 10% traffic
- vs without canary: 30+ minutes at 100% traffic
- **133x reduction in customer impact**

## How to Use This Pipeline

### Prerequisites

**GitHub Secrets (required):**
```
KUBECONFIG_STAGING       # Kubernetes config for staging
KUBECONFIG_PRODUCTION    # Kubernetes config for production
GRAFANA_API_KEY          # For creating deployment annotations
SLACK_WEBHOOK            # For team notifications
```

**Kubernetes Setup:**
```bash
# Create namespaces
kubectl create namespace trading
kubectl create namespace trading-staging
kubectl create namespace monitoring

# Deploy monitoring stack
kubectl apply -f kubernetes/monitoring/

# Create deployments (stable + canary)
kubectl apply -f kubernetes/trading-api/deployment.yaml
```

### Setting Up Secrets

**1. Create Kubernetes config secret:**
```bash
# Get your kubeconfig
cat ~/.kube/config | base64

# Add to GitHub:
# Settings → Secrets → New repository secret
# Name: KUBECONFIG_PRODUCTION
# Value: <base64-encoded-config>
```

**2. Create Grafana API key:**
```bash
# In Grafana: Configuration → API Keys → New API Key
# Add to GitHub Secrets as GRAFANA_API_KEY
```

**3. Create Slack webhook:**
```bash
# In Slack: Apps → Incoming Webhooks → Add to Workspace
# Copy webhook URL
# Add to GitHub Secrets as SLACK_WEBHOOK
```

### Testing the Pipeline

**Test 1: Pull Request (Build & Test only)**
```bash
git checkout -b feature/new-feature
# Make changes
git commit -m "Add new feature"
git push origin feature/new-feature
# Create PR in GitHub
# Pipeline runs: Build → Test → Report
```

**Test 2: Deploy to Staging**
```bash
git checkout develop
# Make changes
git commit -m "Update API"
git push origin develop
# Pipeline runs: Build → Test → Deploy Staging → Smoke Tests
```

**Test 3: Deploy to Production**
```bash
git checkout main
git merge develop
git push origin main
# Pipeline runs: Full canary deployment with monitoring
```

## Understanding the Monitoring Stage

This is the most critical part - it's what prevents bad deployments:

```yaml
monitor-canary:
  runs-on: ubuntu-latest
  steps:
    - name: Monitor for 10 minutes
      run: |
        for i in {1..20}; do  # 20 checks x 30s = 10 min
          # Query Prometheus
          CANARY_ERRORS=$(curl prometheus...)
          STABLE_ERRORS=$(curl prometheus...)
          
          # Compare
          if [ $CANARY_ERRORS > $STABLE_ERRORS * 2 ]; then
            echo "FAIL"
            exit 1  # Triggers rollback
          fi
          
          sleep 30
        done
```

**What happens:**
1. Pipeline queries Prometheus every 30 seconds
2. Compares canary metrics to stable baseline
3. If ANY metric fails threshold → Job fails
4. Job failure → Triggers rollback step
5. Rollback step executes automatically
6. Team gets notified

**This is automation at its finest!**

## Interview Talking Points

### "How do you integrate monitoring into CI/CD?"

**Your answer:**

"I build monitoring directly into the deployment pipeline. After deploying a canary to 10% of traffic, the pipeline continuously queries Prometheus every 30 seconds for 10 minutes.

It compares canary metrics to stable baseline:
- If canary error rate is 2x higher → auto-rollback
- If canary latency is 1.5x higher → auto-rollback  
- If order success rate drops below 99.99% → immediate rollback

This caught a latency regression at VISA during canary deployment. Auto-rollback triggered in 90 seconds. Total impact: 3 minutes at 10% traffic instead of 40+ minutes at 100%.

For CFI, I'd add trading-specific checks: order execution success, settlement time, market data freshness. Any violation of SLOs triggers automatic rollback."

### "Walk me through your deployment process"

**Your answer:**

"The pipeline has 5 stages:

Stage 1: Build & Test - standard CI
Stage 2: Deploy to staging first for smoke tests
Stage 3: Deploy canary to 10% of production
Stage 4: Monitor canary for 10 minutes - THIS IS CRITICAL
  - Query Prometheus comparing canary vs stable
  - Auto-rollback if metrics degrade
Stage 5: If healthy, promote to 100% gradually

The key innovation is Stage 4 - automated health monitoring with auto-rollback. Most teams do canary but rely on manual monitoring. We automate it, which means issues get caught in seconds, not minutes."

## Production Best Practices

### For CFI Trading Platform

**Market-hours awareness:**
```yaml
# Don't deploy during market hours without approval
if [[ $(date +%H) -ge 9 && $(date +%H) -le 16 ]]; then
  echo "Market hours - require manual approval"
  # Wait for approval
fi
```

**Extended monitoring for critical services:**
```yaml
# Monitor canary for 20 minutes (not 10) for order execution service
MONITORING_DURATION=1200  # 20 minutes
```

**Stricter thresholds:**
```yaml
# For trading platform, use stricter canary thresholds
ERROR_THRESHOLD=1.5  # Fail if 1.5x (not 2x)
LATENCY_THRESHOLD=1.2  # Fail if 1.2x (not 1.5x)
```

## Troubleshooting

### Pipeline fails at "Monitor Canary" stage

**Possible causes:**
1. **Prometheus unreachable** - Check PROMETHEUS_URL
2. **No metrics from canary** - Pods not exposing /metrics?
3. **Metrics don't have version label** - Check pod labels
4. **Threshold too strict** - Adjust ERROR_THRESHOLD

**Debug:**
```bash
# Check if canary pods are labeled correctly
kubectl get pods -n trading -l version=canary --show-labels

# Check if metrics are exposed
kubectl port-forward -n trading <canary-pod> 9090:9090
curl localhost:9090/metrics | grep version

# Check Prometheus can scrape
kubectl port-forward -n monitoring svc/prometheus 9090:9090
# Visit http://localhost:9090/targets
```

### Rollback doesn't work

**Check:**
```bash
# Verify rollback command works manually
kubectl rollout undo deployment/trading-api-canary -n trading
kubectl rollout history deployment/trading-api-canary -n trading
```

## Next Steps

1. ✅ Review both pipeline files
2. ✅ Understand the monitoring stage (most important)
3. ✅ Practice explaining the flow out loud
4. ✅ Customize for CFI-specific needs
5. ✅ Add to your GitHub repo
6. ✅ Show CFI in your follow-up

## Real-World Impact

**Without this pipeline:**
- Manual deployments
- No canary testing
- Issues caught by customers
- 30+ minute incident response
- High-stress deployments

**With this pipeline:**
- Fully automated
- Canary with health monitoring
- Issues caught in 3-10 minutes at 10% traffic
- Auto-rollback (no human intervention)
- Confidence in deployments

**For CFI:**
- Deploy multiple times per day safely
- Catch issues before 100% of traders impacted
- Compliance (full audit trail of deployments)
- Reduced on-call burden
- Sleep better at night 😴

---

**Questions? Want to dive deeper into any section?**
