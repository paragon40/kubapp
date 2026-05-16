import time
from collections import deque, defaultdict

from stream.event_bus import consume_all

from metrics.registry import (
    github_push_total,
    github_pr_total,
    github_workflow_run_total,
    github_issue_total,
)

from metrics.health import (
    slo_success_rate,
    error_budget_burn_rate,
    error_budget_remaining,
)

# ============================================================
# SRE CONFIG (REAL SLO MODEL)
# ============================================================

SLO_TARGET = 0.95
ERROR_BUDGET = 1.0 - SLO_TARGET

WINDOW_SECONDS = 300  # 5 min rolling window

# ============================================================
# SLIDING WINDOW STATE (REAL SLI SOURCE)
# ============================================================

workflow_events = deque()  # stores (timestamp, success)

push_events = deque()
issue_events = deque()
pr_events = deque()

# ============================================================
# HELPERS
# ============================================================

def prune_window(window, now):
    while window and now - window[0][0] > WINDOW_SECONDS:
        window.popleft()


def compute_sli():
    """
    SLI = workflow success rate over window
    """
    total = len(workflow_events)
    if total == 0:
        return 1.0

    success = sum(1 for _, ok in workflow_events if ok)
    return success / total


def compute_error_rate(sli):
    return 1.0 - sli


def compute_burn_rate(error_rate):
    if ERROR_BUDGET == 0:
        return 0.0
    return error_rate / ERROR_BUDGET


# ============================================================
# MAIN WORKER LOOP
# ============================================================

def run_worker():
    print("[SRE ENGINE] Worker started...")

    while True:
        now = time.time()
        events = consume_all()

        # -----------------------------
        # INGEST EVENTS
        # -----------------------------
        for event in events:
            repo = event.repo
            etype = event.event_type
            payload = event.payload

            # -------------------------
            # PUSH (activity only)
            # -------------------------
            if etype == "push":
                push_events.append((now, 1))

                github_push_total.labels(
                    repo=repo,
                    commit=payload.get("after", "unknown")
                ).inc()

            # -------------------------
            # PR (activity only)
            # -------------------------
            elif etype == "pull_request":
                pr_events.append((now, 1))

                github_pr_total.labels(
                    repo=repo,
                    action=payload.get("action", "unknown")
                ).inc()

            # -------------------------
            # ISSUES (activity only)
            # -------------------------
            elif etype == "issues":
                issue_events.append((now, 1))

                github_issue_total.labels(
                    repo=repo,
                    action=payload.get("action", "unknown"),
                    state=payload.get("issue", {}).get("state", "unknown"),
                ).inc()

            # -------------------------
            # WORKFLOW RUN (REAL SLI SIGNAL)
            # -------------------------
            elif etype == "workflow_run":
                run = payload.get("workflow_run", {})

                conclusion = run.get("conclusion", "failure")
                success = 1 if conclusion == "success" else 0

                workflow_events.append((now, success))

                github_workflow_run_total.labels(
                    repo=repo,
                    workflow=run.get("name", "unknown"),
                    status=run.get("status", "unknown"),
                    conclusion=conclusion,
                ).inc()

        # -----------------------------
        # PRUNE OLD DATA (ROLLING WINDOW)
        # -----------------------------
        prune_window(workflow_events, now)
        prune_window(push_events, now)
        prune_window(issue_events, now)
        prune_window(pr_events, now)

        # -----------------------------
        # COMPUTE SLO
        # -----------------------------
        sli = compute_sli()
        error_rate = compute_error_rate(sli)
        burn_rate = compute_burn_rate(error_rate)

        remaining_budget = max(0.0, ERROR_BUDGET - error_rate)

        # -----------------------------
        # EXPORT TO PROMETHEUS
        # -----------------------------
        # NOTE: currently single-repo assumption (can extend later)
        repo = "default"

        slo_success_rate.labels(repo=repo).set(sli)
        error_budget_burn_rate.labels(repo=repo).set(burn_rate)
        error_budget_remaining.labels(repo=repo).set(remaining_budget)

        # -----------------------------
        # LOGGING (SRE SIGNAL OUTPUT)
        # -----------------------------
        print(
            f"[SLO] "
            f"sl={sli:.3f} "
            f"err={error_rate:.3f} "
            f"burn={burn_rate:.2f} "
            f"budget_left={remaining_budget:.3f} "
            f"window={WINDOW_SECONDS}s"
        )

        time.sleep(5)
