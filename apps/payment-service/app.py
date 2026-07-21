"""
Payment Service - Handles payment processing
Production Issue Scenarios:
- High latency (external payment gateway slow)
- 5xx errors under load
- Connection pool exhaustion
"""

from flask import Flask, jsonify, request
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
import time
import os
import logging
import random

app = Flask(__name__)
logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
logger = logging.getLogger(__name__)

REQUEST_COUNT = Counter('http_requests_total', 'Total HTTP requests', ['method', 'endpoint', 'status'])
REQUEST_LATENCY = Histogram('http_request_duration_seconds', 'Request latency', ['endpoint'])
PAYMENT_PROCESSED = Counter('payments_processed_total', 'Payments processed', ['status'])

payments_db = {}

# --- PRODUCTION ISSUE: Simulate intermittent failures ---
FAILURE_RATE = float(os.getenv("FAILURE_RATE", "0.0"))  # Set to 0.3 for 30% failure rate


@app.before_request
def before_request():
    request.start_time = time.time()


@app.after_request
def after_request(response):
    latency = time.time() - request.start_time
    REQUEST_COUNT.labels(method=request.method, endpoint=request.path, status=response.status_code).inc()
    REQUEST_LATENCY.labels(endpoint=request.path).observe(latency)
    return response


@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "healthy", "service": "payment-service"})


@app.route('/ready', methods=['GET'])
def ready():
    return jsonify({"status": "ready"})


@app.route('/api/payments', methods=['POST'])
def process_payment():
    """Process a payment request."""
    data = request.get_json()
    if not data or 'order_id' not in data or 'amount' not in data:
        return jsonify({"error": "order_id and amount required"}), 400

    # --- PRODUCTION ISSUE: Simulated latency spike ---
    # Simulates external payment gateway being slow
    if os.getenv("SIMULATE_LATENCY") == "true":
        delay = random.uniform(3, 8)  # 3-8 seconds
        logger.warning(f"Simulating latency: {delay:.1f}s")
        time.sleep(delay)

    # --- PRODUCTION ISSUE: Random 500 errors ---
    if random.random() < FAILURE_RATE:
        logger.error(f"Payment processing failed (simulated) for order {data['order_id']}")
        PAYMENT_PROCESSED.labels(status="error").inc()
        return jsonify({"error": "payment gateway error", "retryable": True}), 500

    payment_id = f"pay_{len(payments_db) + 1}"
    payment = {
        "id": payment_id,
        "order_id": data["order_id"],
        "user_id": data.get("user_id"),
        "amount": data["amount"],
        "status": "completed",
        "processed_at": time.strftime("%Y-%m-%dT%H:%M:%SZ")
    }
    payments_db[payment_id] = payment

    logger.info(f"Payment {payment_id} processed: ${data['amount']}")
    PAYMENT_PROCESSED.labels(status="success").inc()
    return jsonify(payment), 201


@app.route('/api/payments', methods=['GET'])
def list_payments():
    return jsonify({"payments": list(payments_db.values()), "count": len(payments_db)})


@app.route('/metrics', methods=['GET'])
def metrics():
    return generate_latest(), 200, {'Content-Type': CONTENT_TYPE_LATEST}


if __name__ == '__main__':
    port = int(os.getenv("PORT", 5000))
    app.run(host='0.0.0.0', port=port)
