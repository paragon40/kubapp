from prometheus_client import Counter

github_push_total = Counter(
    "github_push_total",
    "GitHub push events",
    ["repo", "commit"]
)

github_pr_total = Counter(
    "github_pr_total",
    "GitHub PR events",
    ["repo", "action"]
)
