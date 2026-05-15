from flask import Blueprint, request
from handlers.github_events import handle_push, handle_pull_request

github_bp = Blueprint("github", __name__)


@github_bp.route("/webhook/github", methods=["POST"])
def github_webhook():
    event = request.headers.get("X-GitHub-Event")
    payload = request.json

    if event == "push":
        handle_push(payload)

    elif event == "pull_request":
        handle_pull_request(payload)

    return "ok", 200

