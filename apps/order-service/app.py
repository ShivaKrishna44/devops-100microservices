"""
Order Service - Handles order creation, status, payment integration
Production Issue Scenarios:
- Circuit breaker pattern (payment service down)
- Request timeout cascading
- OOMKilled (large payload processing)
"""

from flask import Flask, jsonify, request
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
import time
import os
import logging
import requests

app = Flask(__name__)
logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
logger = logging.getLogger(__name__)

# Prometheus metrics
REQUEST_COUNT = Counter('http_requests_total', 'Total HTTP requests', ['method', 'endpoint', 'status'])
REQUEST_LATENCY = Histogram('http_request_duration_seconds', 'Request latency', ['endpoint'])
PAYMENT_FAILURES = Counter('payment_call_failures_total', 'Payment service call failures')

# Config
PAYMENT_SERVICE_URL = os.getenv("PAYMENT_SERVICE_URL", "http://payment-service:5000")
USER_SERVICE_URL = os.getenv("USER_SERVICE_URL", "http://user-service:5000")

orders_db = {}


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
    return jsonify({"status": "healthy", "service": "order-service"})


@app.route('/ready', methods=['GET'])
def ready():
    """Check downstream dependencies."""
    try:
        resp = requests.get(f"{PAYMENT_SERVICE_URL}/health", timeout=2)
        payment_ok = resp.status_code == 200
    except Exception:
        payment_ok = False

    if not payment_ok:
        # --- PRODUCTION ISSUE: Cascading failure ---
        # If payment service is down, should order-service report not ready?
        # This can cause all order pods to be removed from service!
        logger.warning("Payment service health check failed")

    return jsonify({"status": "ready", "dependencies": {"payment": payment_ok}})


@app.route('/api/orders', methods=['POST'])
def create_order():
    """Create a new order and call payment service."""
    data = request.get_json()
    if not data or 'user_id' not in data or 'items' not in data:
        return jsonify({"error": "user_id and items required"}), 400

    order_id = str(len(orders_db) + 1)
    total = sum(item.get("price", 0) * item.get("quantity", 1) for item in data["items"])

    # --- PRODUCTION ISSUE: OOMKilled ---
    # Uncomment to simulate processing a huge payload in memory
    # large_data = data.get("items", []) * 100000

    # Call payment service
    payment_status = "pending"
    try:
        # --- PRODUCTION ISSUE: Timeout cascading ---
        # If payment is slow, order service holds connections open
        resp = requests.post(
            f"{PAYMENT_SERVICE_URL}/api/payments",
            json={"order_id": order_id, "amount": total, "user_id": data["user_id"]},
            timeout=5  # 5s timeout
        )
        if resp.status_code == 201:
            payment_status = "confirmed"
        else:
            payment_status = "failed"
            PAYMENT_FAILURES.inc()
    except requests.Timeout:
        logger.error(f"Payment service timeout for order {order_id}")
        payment_status = "timeout"
        PAYMENT_FAILURES.inc()
    except requests.ConnectionError:
        logger.error(f"Payment service unreachable for order {order_id}")
        payment_status = "service_unavailable"
        PAYMENT_FAILURES.inc()

    order = {
        "id": order_id,
        "user_id": data["user_id"],
        "items": data["items"],
        "total": total,
        "payment_status": payment_status,
        "status": "created" if payment_status == "confirmed" else "payment_pending",
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ")
    }
    orders_db[order_id] = order
    logger.info(f"Order {order_id} created, payment: {payment_status}")

    status_code = 201 if payment_status == "confirmed" else 202
    return jsonify(order), status_code


@app.route('/api/orders', methods=['GET'])
def list_orders():
    return jsonify({"orders": list(orders_db.values()), "count": len(orders_db)})


@app.route('/api/orders/<order_id>', methods=['GET'])
def get_order(order_id):
    order = orders_db.get(order_id)
    if not order:
        return jsonify({"error": "order not found"}), 404
    return jsonify(order)


@app.route('/metrics', methods=['GET'])
def metrics():
    return generate_latest(), 200, {'Content-Type': CONTENT_TYPE_LATEST}


if __name__ == '__main__':
    port = int(os.getenv("PORT", 5000))
    app.run(host='0.0.0.0', port=port)
