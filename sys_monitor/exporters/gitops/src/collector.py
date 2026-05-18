from metrics import (
    gitops_app_total,
    gitops_app_healthy_total,
    gitops_app_out_of_sync_total,
    gitops_app_degraded_total,
    gitops_drift_ratio,
    gitops_convergence_score,
)


def collect_metrics():
    """
    Placeholder implementation.
    Later this will query Argo CD Applications.
    """

    total = 10
    healthy = 8
    out_of_sync = 1
    degraded = 1

    drift_ratio = out_of_sync / total if total else 0

    convergence = max(
        0,
        100
        - (out_of_sync / total) * 40
        - (degraded / total) * 40
    )

    gitops_app_total.set(total)
    gitops_app_healthy_total.set(healthy)
    gitops_app_out_of_sync_total.set(out_of_sync)
    gitops_app_degraded_total.set(degraded)
    gitops_drift_ratio.set(drift_ratio)
    gitops_convergence_score.set(convergence)
