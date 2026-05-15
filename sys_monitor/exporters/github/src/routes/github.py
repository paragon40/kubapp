from flask import Blueprint, request

from handlers.github_events import (
    handle_push,
    handle_pull_request,
    handle_workflow_run,
    handle_release,
    handle_issue,
)

github_bp = Blueprint("github", __name__)


@github_bp.route("/webhook/github", methods=["POST"])
def github_webhook():
    event = request.headers.get("X-GitHub-Event")
    payload = request.get_json(silent=True) or {}

    if event == "push":
        handle_push(payload)

    elif event == "pull_request":
        handle_pull_request(payload)

    elif event == "workflow_run":
        handle_workflow_run(payload)

    elif event == "release":
        handle_release(payload)

    elif event == "issues":
        handle_issue(payload)

    return "ok", 200

