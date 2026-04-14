# Local Docker Demo

## Overview

This spins up the full monitoring stack locally via Docker Compose. Useful for demoing, poking around, or just understanding how the pieces fit together.

What runs:
- Prometheus
- Grafana
- Alertmanager
- A sample trading API that generates realistic metrics

---

## Prerequisites

- Docker Desktop
- ~4GB RAM free
- Ports 3000, 8000, 9090, 9093 available

---

## Getting Started

```bash
tar -xzf cfi-devops-demo.tar.gz
cd cfi-devops-demo
docker-compose up -d
sleep 30

# Grafana -> http://localhost:3000 (admin/admin)
# Prometheus -> http://localhost:9090
# Sample API -> http://localhost:8000
```

---

## Things Worth Showing

**Grafana** (`localhost:3000`) -- dashboards with live metrics: order success rate, latency, error rates.

**Prometheus** (`localhost:9090`) -- check Status -> Targets to confirm everything's scraping. The Alerts tab shows what's configured. A few useful queries:

```promql
# Order success rate
(sum(rate(orders_total{status="success"}[5m])) /
 sum(rate(orders_total[5m]))) * 100

# P95 latency
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))
```

**Sample API** -- hit a few endpoints to generate traffic:

```bash
curl http://localhost:8000/health

curl -X POST http://localhost:8000/api/orders \
  -H "Content-Type: application/json" \
  -d '{"type":"market","symbol":"AAPL","quantity":100}'

curl http://localhost:8000/metrics
```

**Triggering an alert** -- stop the app and watch Prometheus pick it up after ~2 min:

```bash
docker-compose stop sample-app
# check http://localhost:9090/alerts and http://localhost:9093
docker-compose start sample-app
```

---

## Canary Deployment Test

```bash
docker-compose --profile canary up -d trading-api-canary

# Stable (port 8080) vs canary (port 8081) -- canary has a higher failure
# rate baked in, so you can compare them side by side in Prometheus
curl http://localhost:8081/api/orders -X POST \
  -H "Content-Type: application/json" \
  -d '{"type":"market"}'
```

Query `rate(orders_total[5m])` to see the difference.

---

## Troubleshooting

**Port conflicts:**
```bash
lsof -i :3000
lsof -i :9090
lsof -i :8000
```

**No metrics showing up:**
```bash
curl http://localhost:8000/metrics
docker-compose restart prometheus
```

**Grafana issues:**
```bash
docker logs cfi-grafana
docker exec -it cfi-grafana grafana-cli admin reset-admin-password admin
```

---

## Cleanup

```bash
docker-compose down                  # stop services
docker-compose down -v               # also delete volumes
docker-compose down -v --rmi all     # full teardown
```

---

## Notes
Most of the demo speaks for itself -- working metrics, real alerts, canary comparison. Worth knowing a handful of PromQL queries off the top of your head before any conversation with CFI, and being able to explain why canary deployments matter rather than just showing the mechanic.