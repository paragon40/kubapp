from metrics.health import github_health_score

REPO_SCORE = {}

def calculate_health(repo: str, event_type: str = None, payload: dict = None):
    current = REPO_SCORE.get(repo, 50)

    # ----------------------------
    # POSITIVE SIGNALS
    # ----------------------------
    if event_type == "push":
        current += 1

    elif event_type == "pull_request":
        current += 2

    elif event_type == "release":
        current += 4

    # ----------------------------
    # NEGATIVE SIGNALS
    # ----------------------------
    elif event_type == "workflow_run":
        conclusion = (payload or {}).get("conclusion", "success")

        if conclusion == "success":
            current += 3
        elif conclusion == "failure":
            current -= 8

    elif event_type == "issues":
        state = (payload or {}).get("issue", {}).get("state", "open")

        if state == "open":
            current -= 2
        elif state == "closed":
            current += 1

    # ----------------------------
    # BOUNDS
    # ----------------------------
    current = max(0, min(100, current))

    REPO_SCORE[repo] = current
    github_health_score.labels(repo=repo).set(current)

    print(f"[HEALTH] repo={repo} score={current}")
