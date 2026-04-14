#!/usr/bin/env python3
"""
CFI Trading Platform - Sample API
Simulates a trading API with Prometheus metrics
"""

from flask import Flask, jsonify, request
from prometheus_client import Counter, Histogram, Gauge, generate_latest
import time
import random
import os

app = Flask(__name__)

# Prometheus metrics
REQUEST_COUNT = Counter(
    'http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status', 'version']
)

REQUEST_DURATION = Histogram(
    'http_request_duration_seconds',
    'HTTP request duration',
    ['method', 'endpoint', 'version']
)

ORDERS_TOTAL = Counter(
    'orders_total',
    'Total orders processed',
    ['status', 'order_type', 'version']
)

ORDER_LATENCY = Histogram(
    'order_execution_seconds',
    'Order execution time',
    ['order_type', 'version']
)

ACTIVE_ORDERS = Gauge(
    'active_orders',
    'Currently active orders',
    ['version']
)

VERSION = os.getenv('VERSION', 'stable')

@app.route('/health')
def health():
    """Health check endpoint"""
    REQUEST_COUNT.labels(method='GET', endpoint='/health', status='200', version=VERSION).inc()
    return jsonify({
        'status': 'healthy',
        'version': VERSION,
        'timestamp': time.time()
    })

@app.route('/metrics')
def metrics():
    """Prometheus metrics endpoint"""
    return generate_latest()

@app.route('/')
def index():
    """Root endpoint - simulates normal API request"""
    start_time = time.time()
    
    # Simulate processing time (100-200ms normally)
    time.sleep(random.uniform(0.1, 0.2))
    
    duration = time.time() - start_time
    REQUEST_DURATION.labels(method='GET', endpoint='/', version=VERSION).observe(duration)
    REQUEST_COUNT.labels(method='GET', endpoint='/', status='200', version=VERSION).inc()
    
    return jsonify({
        'message': 'CFI Trading API',
        'version': VERSION,
        'processing_time_ms': round(duration * 1000, 2)
    })

@app.route('/slow')
def slow():
    """Intentionally slow endpoint - for testing alerts"""
    start_time = time.time()
    
    # Simulate slow processing (500-2000ms)
    time.sleep(random.uniform(0.5, 2.0))
    
    duration = time.time() - start_time
    REQUEST_DURATION.labels(method='GET', endpoint='/slow', version=VERSION).observe(duration)
    REQUEST_COUNT.labels(method='GET', endpoint='/slow', status='200', version=VERSION).inc()
    
    return jsonify({
        'message': 'Slow endpoint',
        'version': VERSION,
        'processing_time_ms': round(duration * 1000, 2)
    })

@app.route('/error')
def error_endpoint():
    """Endpoint that randomly returns errors - for testing alerts"""
    start_time = time.time()
    
    # 30% chance of error
    if random.random() < 0.3:
        REQUEST_COUNT.labels(method='GET', endpoint='/error', status='500', version=VERSION).inc()
        return jsonify({'error': 'Internal server error'}), 500
    
    duration = time.time() - start_time
    REQUEST_DURATION.labels(method='GET', endpoint='/error', version=VERSION).observe(duration)
    REQUEST_COUNT.labels(method='GET', endpoint='/error', status='200', version=VERSION).inc()
    
    return jsonify({'message': 'Success', 'version': VERSION})

@app.route('/api/orders', methods=['POST'])
def create_order():
    """Create a trading order - simulates order execution"""
    start_time = time.time()
    
    data = request.get_json() or {}
    order_type = data.get('type', 'market')
    
    # Simulate order processing
    processing_time = random.uniform(0.05, 0.15)
    time.sleep(processing_time)
    
    # 99.5% success rate (higher for stable, lower for canary to simulate issues)
    if VERSION == 'canary':
        success_rate = 0.98  # 2% failure to trigger alerts
    else:
        success_rate = 0.995
    
    success = random.random() < success_rate
    status = 'success' if success else 'failed'
    
    # Record metrics
    ORDERS_TOTAL.labels(status=status, order_type=order_type, version=VERSION).inc()
    ORDER_LATENCY.labels(order_type=order_type, version=VERSION).observe(processing_time)
    
    duration = time.time() - start_time
    REQUEST_DURATION.labels(method='POST', endpoint='/api/orders', version=VERSION).observe(duration)
    REQUEST_COUNT.labels(
        method='POST',
        endpoint='/api/orders',
        status='200' if success else '500',
        version=VERSION
    ).inc()
    
    if success:
        return jsonify({
            'order_id': f'ORD-{int(time.time())}',
            'status': 'executed',
            'type': order_type,
            'execution_time_ms': round(processing_time * 1000, 2),
            'version': VERSION
        })
    else:
        return jsonify({
            'error': 'Order execution failed',
            'version': VERSION
        }), 500

@app.route('/api/market-data')
def market_data():
    """Get market data - simulates market data feed"""
    start_time = time.time()
    
    # Simulate data retrieval
    time.sleep(random.uniform(0.01, 0.05))
    
    duration = time.time() - start_time
    REQUEST_DURATION.labels(method='GET', endpoint='/api/market-data', version=VERSION).observe(duration)
    REQUEST_COUNT.labels(method='GET', endpoint='/api/market-data', status='200', version=VERSION).inc()
    
    return jsonify({
        'symbols': [
            {'symbol': 'AAPL', 'price': 150.25, 'change': 2.5},
            {'symbol': 'GOOGL', 'price': 2800.50, 'change': -15.3},
            {'symbol': 'MSFT', 'price': 300.75, 'change': 5.2}
        ],
        'timestamp': time.time(),
        'lag_ms': round(duration * 1000, 2),
        'version': VERSION
    })

if __name__ == '__main__':
    print(f"Starting CFI Trading API - Version: {VERSION}")
    print(f"Metrics available at http://localhost:8000/metrics")
    app.run(host='0.0.0.0', port=8000, debug=False)
