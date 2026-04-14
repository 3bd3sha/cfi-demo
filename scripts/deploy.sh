#!/bin/bash
# CFI Trading Platform - Deployment Automation Script
# Implements canary deployment with automated health monitoring

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROMETHEUS_URL="${PROMETHEUS_URL:-http://localhost:9090}"
DEPLOYMENT_NAME="${1:-trading-api}"
NEW_VERSION="${2:-latest}"
NAMESPACE="${3:-trading}"
CANARY_REPLICAS=2
STABLE_REPLICAS=10
MONITORING_DURATION=600  # 10 minutes

echo -e "${GREEN}=== CFI Trading Platform Deployment ===${NC}"
echo "Deployment: $DEPLOYMENT_NAME"
echo "Version: $NEW_VERSION"
echo "Namespace: $NAMESPACE"
echo ""

# Function to check Prometheus connectivity
check_prometheus() {
    echo -e "${YELLOW}Checking Prometheus connectivity...${NC}"
    if ! curl -sf "$PROMETHEUS_URL/-/healthy" > /dev/null; then
        echo -e "${RED}ERROR: Cannot connect to Prometheus at $PROMETHEUS_URL${NC}"
        echo "Deployment aborted - monitoring system unavailable"
        exit 1
    fi
    echo -e "${GREEN}✓ Prometheus is healthy${NC}"
}

# Function to deploy canary
deploy_canary() {
    echo -e "${YELLOW}Deploying canary version...${NC}"
    
    kubectl set image deployment/$DEPLOYMENT_NAME-canary \
        $DEPLOYMENT_NAME=cfi/$DEPLOYMENT_NAME:$NEW_VERSION \
        -n $NAMESPACE
    
    kubectl scale deployment/$DEPLOYMENT_NAME-canary \
        --replicas=$CANARY_REPLICAS \
        -n $NAMESPACE
    
    echo "Waiting for canary rollout..."
    kubectl rollout status deployment/$DEPLOYMENT_NAME-canary -n $NAMESPACE
    
    echo -e "${GREEN}✓ Canary deployed${NC}"
}

# Function to query Prometheus
query_prometheus() {
    local query="$1"
    curl -s "$PROMETHEUS_URL/api/v1/query" \
        --data-urlencode "query=$query" \
        | jq -r '.data.result[0].value[1] // "0"'
}

# Function to check canary health
check_canary_health() {
    echo -e "${YELLOW}Monitoring canary health for $MONITORING_DURATION seconds...${NC}"
    
    local iterations=$((MONITORING_DURATION / 30))
    
    for i in $(seq 1 $iterations); do
        echo -e "\n${YELLOW}Health check $i/$iterations${NC}"
        
        # Check 1: Error Rate
        CANARY_ERRORS=$(query_prometheus 'sum(rate(http_requests_total{version="canary",status=~"5.."}[5m])) / sum(rate(http_requests_total{version="canary"}[5m]))')
        STABLE_ERRORS=$(query_prometheus 'sum(rate(http_requests_total{version="stable",status=~"5.."}[5m])) / sum(rate(http_requests_total{version="stable"}[5m]))')
        
        echo "  Canary error rate: $CANARY_ERRORS"
        echo "  Stable error rate: $STABLE_ERRORS"
        
        # Check if canary errors > 2x stable
        if (( $(echo "$CANARY_ERRORS > $STABLE_ERRORS * 2" | bc -l) )); then
            echo -e "${RED}✗ Canary error rate is 2x higher than stable${NC}"
            return 1
        fi
        
        # Check 2: Latency
        CANARY_P95=$(query_prometheus 'histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{version="canary"}[5m]))')
        STABLE_P95=$(query_prometheus 'histogram_quantile(0.95, rate(http_request_duration_seconds_bucket{version="stable"}[5m]))')
        
        echo "  Canary P95 latency: ${CANARY_P95}s"
        echo "  Stable P95 latency: ${STABLE_P95}s"
        
        # Check if canary P95 > 1.5x stable
        if (( $(echo "$CANARY_P95 > $STABLE_P95 * 1.5" | bc -l) )); then
            echo -e "${RED}✗ Canary latency is 1.5x higher than stable${NC}"
            return 1
        fi
        
        # Check 3: Order Success Rate (CFI-specific)
        SUCCESS_RATE=$(query_prometheus '(sum(rate(orders_total{version="canary",status="success"}[5m])) / sum(rate(orders_total{version="canary"}[5m]))) * 100')
        
        echo "  Order success rate: ${SUCCESS_RATE}%"
        
        if (( $(echo "$SUCCESS_RATE < 99.99" | bc -l) )); then
            echo -e "${RED}✗ Order success rate below 99.99% SLO${NC}"
            return 1
        fi
        
        echo -e "${GREEN}✓ Health check $i passed${NC}"
        
        sleep 30
    done
    
    echo -e "${GREEN}✓ All health checks passed!${NC}"
    return 0
}

# Function to rollback
rollback() {
    echo -e "${RED}Rolling back canary deployment...${NC}"
    
    kubectl rollout undo deployment/$DEPLOYMENT_NAME-canary -n $NAMESPACE
    kubectl scale deployment/$DEPLOYMENT_NAME-canary --replicas=0 -n $NAMESPACE
    
    echo -e "${RED}✗ Deployment failed - rolled back to stable version${NC}"
    
    # Send Slack notification (requires SLACK_WEBHOOK env var)
    if [ -n "$SLACK_WEBHOOK" ]; then
        curl -X POST $SLACK_WEBHOOK \
            -H 'Content-Type: application/json' \
            -d "{\"text\":\"🚨 CFI Deployment FAILED: $DEPLOYMENT_NAME $NEW_VERSION - auto-rolled back\"}"
    fi
    
    exit 1
}

# Function to promote canary
promote_canary() {
    echo -e "${GREEN}Promoting canary to full deployment...${NC}"
    
    # Step 1: Increase canary to 50%
    echo "Scaling canary to 50% traffic..."
    kubectl scale deployment/$DEPLOYMENT_NAME-canary --replicas=5 -n $NAMESPACE
    kubectl scale deployment/$DEPLOYMENT_NAME-stable --replicas=5 -n $NAMESPACE
    sleep 300  # Monitor for 5 minutes
    
    # Step 2: Increase canary to 100%
    echo "Scaling canary to 100% traffic..."
    kubectl scale deployment/$DEPLOYMENT_NAME-canary --replicas=$STABLE_REPLICAS -n $NAMESPACE
    kubectl scale deployment/$DEPLOYMENT_NAME-stable --replicas=0 -n $NAMESPACE
    sleep 300  # Monitor for 5 minutes
    
    # Step 3: Make canary the new stable
    echo "Finalizing deployment..."
    kubectl set image deployment/$DEPLOYMENT_NAME-stable \
        $DEPLOYMENT_NAME=cfi/$DEPLOYMENT_NAME:$NEW_VERSION \
        -n $NAMESPACE
    kubectl scale deployment/$DEPLOYMENT_NAME-stable --replicas=$STABLE_REPLICAS -n $NAMESPACE
    kubectl scale deployment/$DEPLOYMENT_NAME-canary --replicas=0 -n $NAMESPACE
    
    echo -e "${GREEN}✓ Deployment successful!${NC}"
    
    # Send Slack notification
    if [ -n "$SLACK_WEBHOOK" ]; then
        curl -X POST $SLACK_WEBHOOK \
            -H 'Content-Type: application/json' \
            -d "{\"text\":\"✅ CFI Deployment SUCCESS: $DEPLOYMENT_NAME $NEW_VERSION deployed to production\"}"
    fi
}

# Main execution
main() {
    check_prometheus
    deploy_canary
    
    if check_canary_health; then
        promote_canary
    else
        rollback
    fi
}

# Run main function
main
