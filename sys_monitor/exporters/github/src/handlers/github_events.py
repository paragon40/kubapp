from datetime import datetime, timezone

from handlers.health import calculate_health
from ai.anomaly_detector import AnomalyDetector
from metrics.health import github_anomaly_flag

from metrics.registry import (
    github_push_total,
    github_pr_total,
    github_workflow_run_total,
    github_workflow_duration_seconds,
    github_release_total,
    github_issue_total,
    github_change_lead_time_seconds,
)

# In-memory cache of last push timestamp per repo
LAST_PUSH_TS = {}


def handle_push(payload):
    repo = payload.get("repository", {}).get("full_name", "unknown")
    commit = payload.get("after", "unknown")

    github_push_total.labels(repo=repo, commit=commit).inc()
    LAST_PUSH_TS[repo] = datetime.now(timezone.utc).timestamp()
    current_count = github_push_total.labels(repo=repo, commit=commit)._value.get()
    detect_push_anomaly(repo, current_count)
    print(f"[PUSH] repo={repo} commit={commit}")
    calculate_health(repo, "push")

def handle_pull_request(payload):
    repo = payload.get("repository", {}).get("full_name", "unknown")
    action = payload.get("action", "unknown")

    github_pr_total.labels(repo=repo, action=action).inc()

    print(f"[PR] repo={repo} action={action}")
    calculate_health(repo, "pull_request")

def handle_workflow_run(payload):
    repo = payload.get("repository", {}).get("full_name", "unknown")
    run = payload.get("workflow_run", {})

    workflow = run.get("name", "unknown")
    status = run.get("status", "unknown")
    conclusion = run.get("conclusion") or "none"

    github_workflow_run_total.labels(
        repo=repo,
        workflow=workflow,
        status=status,
        conclusion=conclusion,
    ).inc()

    run_started_at = run.get("run_started_at")
    updated_at = run.get("updated_at")

    if run_started_at and updated_at:
        start = datetime.fromisoformat(run_started_at.replace("Z", "+00:00"))
        end = datetime.fromisoformat(updated_at.replace("Z", "+00:00"))
        duration = max((end - start).total_seconds(), 0)

        github_workflow_duration_seconds.labels(
            repo=repo,
            workflow=workflow,
        ).observe(duration)

    print(
        f"[WORKFLOW] repo={repo} workflow={workflow} "
        f"status={status} conclusion={conclusion}"
    )
    calculate_health(repo, "workflow_run")

def handle_release(payload):
    repo = payload.get("repository", {}).get("full_name", "unknown")
    release = payload.get("release", {})

    tag = release.get("tag_name", "unknown")
    version = tag

    github_release_total.labels(
        repo=repo,
        tag=tag,
        version=version,
    ).inc()

    if repo in LAST_PUSH_TS:
        lead_time = datetime.now(timezone.utc).timestamp() - LAST_PUSH_TS[repo]
        github_change_lead_time_seconds.labels(
            repo=repo,
            tag=tag,
        ).set(lead_time)

    print(f"[RELEASE] repo={repo} tag={tag}")
    calculate_health(repo, "release")


def handle_issue(payload):
    repo = payload.get("repository", {}).get("full_name", "unknown")
    action = payload.get("action", "unknown")
    issue = payload.get("issue", {})
    state = issue.get("state", "unknown")

    github_issue_total.labels(
        repo=repo,
        action=action,
        state=state,
    ).inc()

    print(f"[ISSUE] repo={repo} action={action} state={state}")
    calculate_health(repo, "issue")


push_detector = AnomalyDetector()
def detect_push_anomaly(repo, count):
    push_detector.add(count)

    if push_detector.is_anomaly(count):
        github_anomaly_flag.labels(repo=repo, type="push").set(1)
    else:
        github_anomaly_flag.labels(repo=repo, type="push").set(0)

