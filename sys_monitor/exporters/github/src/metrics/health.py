from prometheus_client import Gauge

github_health_score = Gauge(
    "github_health_score",
    "GitOps health score (0-100)",
    ["repo"]
)

github_anomaly_flag = Gauge(
    "github_anomaly_flag",
    "Anomaly detected in GitOps behavior",
    ["repo", "type"]
)
