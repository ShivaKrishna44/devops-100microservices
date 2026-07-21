"""
User Service - Handles user registration, authentication, profiles
Production Issue Scenarios:
- Memory leak (uncomment leak simulation)
- Slow response times (DB connection pool exhaustion)
- Health check failures
"""

from flask import Flask, jsonify, request
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
import time
import os
import logging

app = Flask(__name__)

# Logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
logger = logging.getLogger(__name__)

# Prometheus metrics
REQUEST_COUNT = Counter('http_requests_total', 'Total HTTP requests', ['method', 'endpoint', 'status'])
REQUEST_LATENCY = Histogram('http_request_duration_seconds', 'Request latency', ['endpoint'])

# Simulated database
users_db = {}

# --- PRODUCTION ISSUE: Memory Leak Simulation ---
# Uncomment to simulate a memory leak
# leaked_data = []


@app.before_request
def before_request():
    request.start_time = time.time()


@app.after_request
def after_request(response):
    latency = time.time() - request.start_time
    REQUEST_COUNT.labels(method=request.method, endpoint=request.path, status=response.status_code).inc()
    REQUEST_LATENCY.labels(endpoint=request.path).observe(latency)

    # --- PRODUCTION ISSUE: Memory Leak ---
    # Uncomment to simulate accumulating data that's never freed
    # leaked_data.append("x" * 1024)  # Leak 1KB per request

    return response


@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint for Kubernetes liveness/readiness probes."""
    return jsonify({"status": "healthy", "service": "user-service", "version": os.getenv("APP_VERSION", "1.0.0")})


@app.route('/ready', methods=['GET'])
def ready():
    """Readiness check - verifies dependencies are available."""
    # --- PRODUCTION ISSUE: DB connection check fails intermittently ---
    # Simulate: if random.random() < 0.1: return jsonify({"status": "not ready"}), 503
    return jsonify({"status": "ready"})


@app.route('/api/users', methods=['GET'])
def list_users():
    """List all users."""
    logger.info(f"Listing {len(users_db)} users")
    return jsonify({"users": list(users_db.values()), "count": len(users_db)})


@app.route('/api/users', methods=['POST'])
def create_user():
    """Create a new user."""
    data = request.get_json()
    if not data or 'email' not in data:
        return jsonify({"error": "email is required"}), 400

    user_id = str(len(users_db) + 1)
    user = {
        "id": user_id,
        "email": data["email"],
        "name": data.get("name", ""),
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ")
    }
    users_db[user_id] = user
    logger.info(f"Created user: {user_id}")
    return jsonify(user), 201


@app.route('/api/users/<user_id>', methods=['GET'])
def get_user(user_id):
    """Get user by ID."""
    # --- PRODUCTION ISSUE: Slow Response Simulation ---
    # Uncomment to simulate DB latency spike
    # time.sleep(2)

    user = users_db.get(user_id)
    if not user:
        return jsonify({"error": "user not found"}), 404
    return jsonify(user)


@app.route('/metrics', methods=['GET'])
def metrics():
    """Prometheus metrics endpoint."""
    return generate_latest(), 200, {'Content-Type': CONTENT_TYPE_LATEST}


if __name__ == '__main__':
    port = int(os.getenv("PORT", 5000))
    app.run(host='0.0.0.0', port=port)
