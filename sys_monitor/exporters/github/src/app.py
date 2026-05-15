from flask import Flask, request
from metrics.registry import github_push_total, github_pr_total

app = Flask(__name__)

@app.route("/", methods=["GET"])
def home():
    return "GitHub Exporter Running", 200


@app.route("/webhook/github", methods=["POST"])
def github_webhook():
    event = request.headers.get("X-GitHub-Event")
    payload = request.json

    repo = payload.get("repository", {}).get("full_name", "unknown")

    if event == "push":
        commit = payload.get("after", "unknown")
        github_push_total.labels(repo=repo, commit=commit).inc()

    if event == "pull_request":
        action = payload.get("action", "unknown")
        github_pr_total.labels(repo=repo, action=action).inc()

    return "ok", 200


@app.route("/metrics")
def metrics():
    from prometheus_client import generate_latest
    return generate_latest(), 200, {"Content-Type": "text/plain"}


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=3000)

