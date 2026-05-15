from metrics.health import github_health_score

# In-memory score store per repository.
# Starts each repo at a neutral score of 50.
REPO_SCORE = {}


def calculate_health(repo: str):
    """
    Simple event-driven GitOps health score.
    Rules:
    - New repositories start at 50.
    - Every GitHub event (push, PR, workflow, release, issue)
      increases the score by 2.
    - Score is capped between 0 and 100.

    This gives you a stable and deterministic score without relying on
    Prometheus internal counter state or specific metric labels.
    """
    current_score = REPO_SCORE.get(repo, 50)

    # Reward activity
    current_score += 2

    # Clamp score to 0-100
    current_score = max(0, min(100, current_score))

    # Save state
    REPO_SCORE[repo] = current_score

    # Export to Prometheus
    github_health_score.labels(repo=repo).set(current_score)

    print(f"[HEALTH] repo={repo} score={current_score}")

