# ./exporters/github/src/sre_engine/worker.py

import time

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
# SLO CONFIG
# ============================================================

SLO_TARGET = 0.95
ERROR_BUDGET = 1.0 - SLO_TARGET


# ============================================================
# PURE SLI COMPUTATION
# ============================================================

def compute_sli(workflow_events):
    if not workflow_events:
        return 1.0

    success = sum(1 for e in workflow_events if e["success"])
    return success / len(workflow_events)


def compute_error_rate(sli):
    return 1.0 - sli


def compute_burn_rate(error_rate):
    if ERROR_BUDGET == 0:
        return 0.0
    return error_rate / ERROR_BUDGET


# ============================================================
# WORKER LOOP (SQLITE SOURCE OF TRUTH)
# ============================================================

def run_worker():
    print("[SRE ENGINE] Worker started...")

    while True:
        events = consume_all()

        workflow_events = []

        # --------------------------------------------------------
        # PROCESS EVENTS (FROM SQLITE REPLAY)
        # --------------------------------------------------------
        for event in events:
            repo = event.get("repo", "unknown")
            etype = event.get("event_type")
            payload = event.get("payload", {})

            # PUSH
            if etype == "push":
                github_push_total.labels(
                    repo=repo,
                    commit=payload.get("after", "unknown")
                ).inc()

            # PR
            elif etype == "pull_request":
                github_pr_total.labels(
                    repo=repo,
                    action=payload.get("action", "unknown")
                ).inc()

            # ISSUES
            elif etype == "issues":
                github_issue_total.labels(
                    repo=repo,
                    action=payload.get("action", "unknown"),
                    state=payload.get("issue", {}).get("state", "unknown"),
                ).inc()

            # WORKFLOW RUN (REAL SLI SIGNAL)
            elif etype in ("workflow_run_success", "workflow_run_failure", "workflow_run_unknown"):
                run = payload.get("workflow_run", {})

                success = 1 if etype == "workflow_run_success" else 0

                workflow_events.append({
                    "repo": repo,
                    "success": success
                })

                github_workflow_run_total.labels(
                    repo=repo,
                    workflow=run.get("name", "unknown"),
                    status=run.get("status", "unknown"),
                    conclusion=etype,
                ).inc()

        # --------------------------------------------------------
        # COMPUTE SLO (FROM REAL SQLITE DATA ONLY)
        # --------------------------------------------------------
        sli = compute_sli(workflow_events)
        error_rate = compute_error_rate(sli)
        burn_rate = compute_burn_rate(error_rate)
        remaining_budget = max(0.0, ERROR_BUDGET - error_rate)

        repo = "default"

        slo_success_rate.labels(repo=repo).set(sli)
        error_budget_burn_rate.labels(repo=repo).set(burn_rate)
        error_budget_remaining.labels(repo=repo).set(remaining_budget)

        print(
            f"[SLO] sli={sli:.3f} err={error_rate:.3f} "
            f"burn={burn_rate:.2f} budget_left={remaining_budget:.3f}"
        )

        time.sleep(5)
