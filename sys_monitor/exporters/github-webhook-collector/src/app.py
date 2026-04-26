from flask import Flask, request
from datetime import datetime

from prometheus_client import Counter, generate_latest, CONTENT_TYPE_LATEST

app = Flask(__name__)

# ---------------------------
# METRICS (GitOps signals)
# ---------------------------
github_push_total = Counter(
    "github_push_total",
    "Total number of GitHub push events",
    ["repo", "commit"]
)

github_pr_total = Counter(
    "github_pr_total",
    "Total number of GitHub pull request events",
    ["repo", "action"]
)

github_merge_total = Counter(
    "github_merge_total",
    "Total number of GitHub merge events"
)

# ---------------------------
# HOME PAGE
# ---------------------------
@app.route("/", methods=["GET"])
def home():
    now = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC")

    return f"""
    <html>
        <head>
            <title>GitOps Webhook Collector</title>
        </head>
        <body style="font-family: Arial; padding: 20px;">
            <h2>Project: Kubapp</h2>
            <h2>GitOps Observability Collector</h2>

            <p><b>Status:</b> Running</p>
            <p><b>Time:</b> {now}</p>

            <hr>

            <ul>
                <li>/webhook/github → GitHub events</li>
                <li>/metrics → Prometheus scrape endpoint</li>
            </ul>
        </body>
    </html>
    """

# ---------------------------
# GITHUB WEBHOOK
# ---------------------------
@app.route("/webhook/github", methods=["POST"])
def github_webhook():
    event = request.headers.get("X-GitHub-Event")
    payload = request.json

    if event == "push":
        repo = payload["repository"]["full_name"]
        commit = payload["after"]

        github_push_total.labels(
            repo=repo,
            commit=commit
        ).inc()

        print(f"[PUSH] repo={repo} commit={commit}")

    elif event == "pull_request":
        repo = payload["repository"]["full_name"]
        action = payload["action"]

        github_pr_total.labels(
            repo=repo,
            action=action
        ).inc()

    return "ok", 200

# ---------------------------
# PROMETHEUS METRICS ENDPOINT
# ---------------------------
@app.route("/metrics", methods=["GET"])
def metrics():
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=3000)
