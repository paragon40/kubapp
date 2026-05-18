from kubernetes import client, config

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
    REAL GitOps state collector using Kubernetes API
    """

    try:
        config.load_kube_config()
    except Exception:
        config.load_incluster_config()

    # Argo CD Applications (CRD)
    api = client.CustomObjectsApi()

    apps = api.list_cluster_custom_object(
        group="argoproj.io",
        version="v1alpha1",
        plural="applications"
    )

    items = apps.get("items", [])

    total = len(items)
    healthy = 0
    out_of_sync = 0
    degraded = 0

    for app in items:
        status = app.get("status", {})
        sync = status.get("sync", {}).get("status", "")
        health = status.get("health", {}).get("status", "")

        if sync == "Synced":
            healthy += 1
        else:
            out_of_sync += 1

        if health in ("Degraded", "Missing", "Unknown"):
            degraded += 1

    drift_ratio = (out_of_sync / total) if total else 0.0

    convergence = 100
    convergence -= drift_ratio * 50
    convergence -= (degraded / total) * 50 if total else 0

    # clamp
    convergence = max(0, min(100, convergence))

    # expose metrics
    gitops_app_total.set(total)
    gitops_app_healthy_total.set(healthy)
    gitops_app_out_of_sync_total.set(out_of_sync)
    gitops_app_degraded_total.set(degraded)
    gitops_drift_ratio.set(drift_ratio)
    gitops_convergence_score.set(convergence)
