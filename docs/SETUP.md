# CFI DevOps Demo - Setup Guide

This guide walks you through setting up the complete monitoring and deployment infrastructure locally.

## Prerequisites

- **Docker Desktop** or **Minikube** (for Kubernetes)
- **kubectl** (Kubernetes CLI)
- **Helm** (Kubernetes package manager)
- **Terraform** >= 1.0
- **Git**

## Quick Start (5 minutes)

### Option 1: Docker Compose (Fastest)

```bash
# Clone repository
git clone https://github.com/yourusername/cfi-devops-demo
cd cfi-devops-demo

# Start monitoring stack
docker-compose up -d

# Access dashboards
open http://localhost:3000  # Grafana (admin/admin)
open http://localhost:9090  # Prometheus
open http://localhost:9093  # Alertmanager
```

### Option 2: Kubernetes (Production-like)

```bash
# Start minikube
minikube start --cpus=4 --memory=8192

# Deploy monitoring stack
kubectl create namespace monitoring
kubectl create namespace trading

# Deploy Prometheus
kubectl apply -f kubernetes/monitoring/

# Deploy sample trading API
kubectl apply -f kubernetes/trading-api/

# Access Grafana
kubectl port-forward -n monitoring svc/grafana 3000:3000

# Access Prometheus
kubectl port-forward -n monitoring svc/prometheus 9090:9090
```

## Detailed Setup

### 1. Prometheus Setup

```bash
# Create monitoring namespace
kubectl create namespace monitoring

# Deploy Prometheus
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/prometheus \
  --namespace monitoring \
  --values prometheus/values.yaml

# Verify deployment
kubectl get pods -n monitoring
```

### 2. Grafana Setup

```bash
# Deploy Grafana
helm repo add grafana https://grafana.github.io/helm-charts
helm install grafana grafana/grafana \
  --namespace monitoring \
  --set adminPassword=admin

# Get Grafana password
kubectl get secret --namespace monitoring grafana \
  -o jsonpath="{.data.admin-password}" | base64 --decode

# Port-forward to access
kubectl port-forward -n monitoring svc/grafana 3000:80
```

### 3. Import Grafana Dashboards

```bash
# Access Grafana at http://localhost:3000

# 1. Add Prometheus data source
#    Configuration > Data Sources > Add Prometheus
#    URL: http://prometheus-server

# 2. Import dashboards
#    Click '+' > Import
#    Upload grafana/trading-overview.json
#    Upload grafana/system-health.json
```

### 4. Deploy Trading Services

```bash
# Deploy trading API
kubectl apply -f kubernetes/trading-api/deployment.yaml

# Verify deployment
kubectl get pods -n trading
kubectl logs -n trading -l app=trading-api

# Check metrics endpoint
kubectl port-forward -n trading svc/trading-api 8080:80
curl http://localhost:8080/metrics
```

### 5. Test Alerting

```bash
# Trigger a test alert by stopping a service
kubectl scale deployment/trading-api --replicas=0 -n trading

# Check Alertmanager
open http://localhost:9093

# Verify alert appears in Grafana
# Dashboards > Alerts

# Restore service
kubectl scale deployment/trading-api --replicas=5 -n trading
```

### 6. Test Deployment Automation

```bash
# Make script executable
chmod +x scripts/deploy.sh

# Run deployment with monitoring
./scripts/deploy.sh trading-api v1.0.1 trading

# Watch the automated health checks
# Script will:
# - Deploy canary (10% traffic)
# - Monitor for 10 minutes
# - Auto-rollback if issues detected
# - Promote to 100% if healthy
```

## Terraform Setup

### Initialize Remote State

```bash
cd terraform

# Initialize Terraform
terraform init

# Plan infrastructure
terraform plan -var-file=prod.tfvars

# Apply (creates monitoring infrastructure)
terraform apply
```

### What Gets Created

- S3 bucket for state storage (with versioning & encryption)
- DynamoDB table for state locking
- Prometheus server (EC2 or EKS)
- Grafana server
- AlertManager
- All networking & security groups

## Troubleshooting

### Prometheus Not Scraping Targets

```bash
# Check Prometheus targets
open http://localhost:9090/targets

# Common issues:
# 1. ServiceMonitor not matching labels
kubectl get servicemonitor -n monitoring

# 2. Network policies blocking traffic
kubectl get networkpolicies -n trading

# 3. Pods not exposing metrics port
kubectl describe pod -n trading <pod-name>
```

### Grafana Can't Connect to Prometheus

```bash
# Test connectivity from Grafana pod
kubectl exec -n monitoring <grafana-pod> -- \
  curl http://prometheus-server:80/-/healthy

# Check service DNS
kubectl run -it --rm debug --image=nicolaka/netshoot \
  --restart=Never -- nslookup prometheus-server.monitoring.svc.cluster.local
```

### Alerts Not Firing

```bash
# Check alert rules loaded
open http://localhost:9090/rules

# Check alert state
open http://localhost:9090/alerts

# View Alertmanager config
kubectl get configmap -n monitoring alertmanager-config -o yaml

# Check Alertmanager logs
kubectl logs -n monitoring -l app=alertmanager
```

## Production Considerations

### Security

```bash
# 1. Enable RBAC
kubectl create serviceaccount prometheus -n monitoring
kubectl create clusterrolebinding prometheus \
  --clusterrole=cluster-admin \
  --serviceaccount=monitoring:prometheus

# 2. Use secrets for credentials
kubectl create secret generic grafana-credentials \
  --from-literal=admin-password=<strong-password> \
  -n monitoring

# 3. Enable TLS
# Configure ingress with cert-manager for HTTPS
```

### Scaling

```bash
# Scale Prometheus for high load
helm upgrade prometheus prometheus-community/prometheus \
  --namespace monitoring \
  --set server.replicaCount=3 \
  --set server.resources.requests.memory=4Gi

# Use Thanos for long-term storage
helm install thanos bitnami/thanos \
  --namespace monitoring
```

### High Availability

```bash
# Deploy Prometheus in HA mode
helm upgrade prometheus prometheus-community/prometheus \
  --set server.replicaCount=2 \
  --set alertmanager.replicaCount=3

# Use external storage (S3)
# Configure in values.yaml:
# server:
#   persistentVolume:
#     enabled: false
#   statefulSet:
#     enabled: true
```

## Next Steps

1. ✅ Review [ARCHITECTURE.md](ARCHITECTURE.md) for design decisions
2. ✅ Read [MONITORING_STRATEGY.md](MONITORING_STRATEGY.md) for alert philosophy
3. ✅ Check [INCIDENT_RESPONSE.md](INCIDENT_RESPONSE.md) for runbooks
4. ✅ Explore Grafana dashboards
5. ✅ Test deployment automation script
6. ✅ Customize for your environment

## Support

For questions or issues with this demonstration:

**Abdalraheem Asha**  
Email: abd.m.asha@outlook.com  
Phone: +962-776171281
