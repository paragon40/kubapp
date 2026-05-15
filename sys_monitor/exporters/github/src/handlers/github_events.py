from metrics.registry import github_push_total, github_pr_total


def handle_push(payload):
    repo = payload.get("repository", {}).get("full_name", "unknown")
    commit = payload.get("after", "unknown")

    github_push_total.labels(repo=repo, commit=commit).inc()

    print(f"[PUSH] repo={repo} commit={commit}")


def handle_pull_request(payload):
    repo = payload.get("repository", {}).get("full_name", "unknown")
    action = payload.get("action", "unknown")

    github_pr_total.labels(repo=repo, action=action).inc()

    print(f"[PR] repo={repo} action={action}")
