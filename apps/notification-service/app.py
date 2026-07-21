"""
Notification Service - Sends emails, SMS, push notifications
Production Issue Scenarios:
- Queue backlog (SQS/SNS lag)
- Rate limiting from external providers
- Dead letter queue overflow
"""

from flask import Flask, jsonify, request
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
import time
import os
import logging

app = Flask(__name__)
logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
logger = logging.getLogger(__name__)

REQUEST_COUNT = Counter('http_requests_total', 'Total HTTP requests', ['method', 'endpoint', 'status'])
REQUEST_LATENCY = Histogram('http_request_duration_seconds', 'Request latency', ['endpoint'])
NOTIFICATIONS_SENT = Counter('notifications_sent_total', 'Notifications sent', ['channel', 'status'])

notifications_db = []


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
    return jsonify({"status": "healthy", "service": "notification-service"})


@app.route('/ready', methods=['GET'])
def ready():
    return jsonify({"status": "ready"})


@app.route('/api/notifications', methods=['POST'])
def send_notification():
    """Send a notification via email/sms/push."""
    data = request.get_json()
    if not data or 'channel' not in data or 'message' not in data:
        return jsonify({"error": "channel and message required"}), 400

    channel = data["channel"]  # email, sms, push
    notification = {
        "id": str(len(notifications_db) + 1),
        "channel": channel,
        "recipient": data.get("recipient", ""),
        "message": data["message"],
        "status": "sent",
        "sent_at": time.strftime("%Y-%m-%dT%H:%M:%SZ")
    }

    # --- PRODUCTION ISSUE: Rate limiting ---
    # if len(notifications_db) > 100:
    #     return jsonify({"error": "rate limit exceeded", "retry_after": 60}), 429

    notifications_db.append(notification)
    NOTIFICATIONS_SENT.labels(channel=channel, status="sent").inc()
    logger.info(f"Notification sent via {channel} to {data.get('recipient')}")

    return jsonify(notification), 201


@app.route('/api/notifications', methods=['GET'])
def list_notifications():
    return jsonify({"notifications": notifications_db[-50:], "total": len(notifications_db)})


@app.route('/metrics', methods=['GET'])
def metrics():
    return generate_latest(), 200, {'Content-Type': CONTENT_TYPE_LATEST}


if __name__ == '__main__':
    port = int(os.getenv("PORT", 5000))
    app.run(host='0.0.0.0', port=port)
