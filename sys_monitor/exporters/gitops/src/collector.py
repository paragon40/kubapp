from kubernetes import client, config

from metrics import (
    gitops_app_total,
    gitops_app_healthy_total,
    gitops_app_out_of_sync_total,
    gitops_app_degraded_total,
    gitops_drift_ratio,
    gitops_convergence_score
)

GROUP = "argoproj.io"
VERSION = "v1alpha1"
PLURAL = "applications"


def collect_metrics():
    try:
        config.load_kube_config()

        api = client.CustomObjectsApi()

        response = api.list_cluster_custom_object(
            group=GROUP,
            version=VERSION,
            plural=PLURAL
        )

        apps = response.get("items", [])

        total = len(apps)
        healthy = 0
        out_of_sync = 0
        degraded = 0

        for app in apps:
            status = app.get("status", {})

            health = status.get("health", {}).get("status", "")
            sync = status.get("sync", {}).get("status", "")

            if health == "Healthy":
                healthy += 1

            if sync != "Synced":
                out_of_sync += 1

            if health in ["Degraded", "Missing"]:
                degraded += 1

        drift_ratio = (out_of_sync / total) if total else 0
        convergence = (healthy / total) if total else 0

        gitops_app_total.set(total)
        gitops_app_healthy_total.set(healthy)
        gitops_app_out_of_sync_total.set(out_of_sync)
        gitops_app_degraded_total.set(degraded)
        gitops_drift_ratio.set(drift_ratio)
        gitops_convergence_score.set(convergence)

    except Exception as e:
        print(f"[GitOps ERROR] {e}")
