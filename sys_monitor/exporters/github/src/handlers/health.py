from metrics.health import github_health_score
from metrics.registry import (
    github_push_total,
    github_pr_total,
    github_workflow_run_total,
)

def calculate_health(repo: str):
    # Simple heuristic model

    push = github_push_total.labels(repo=repo, commit="unknown")._value.get() or 0
    pr = github_pr_total.labels(repo=repo, action="unknown")._value.get() or 0

    workflow_total = github_workflow_run_total.labels(
        repo=repo,
        workflow="unknown",
        status="unknown",
        conclusion="success"
    )._value.get() or 0

    failure_total = github_workflow_run_total.labels(
        repo=repo,
        workflow="unknown",
        status="unknown",
        conclusion="failure"
    )._value.get() or 0

    # Normalize simple score
    score = (
        min(workflow_total * 2, 40) +
        min(pr * 3, 20) +
        min(push * 2, 20) -
        min(failure_total * 5, 30)
    )

    score = max(0, min(100, score))

    github_health_score.labels(repo=repo).set(score)

