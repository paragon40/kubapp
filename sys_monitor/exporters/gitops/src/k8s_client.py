from kubernetes import client, config


def get_k8s_client():
    """
    Try loading local kubeconfig first.
    If unavailable, fall back to in-cluster config.
    """
    try:
        config.load_kube_config()
        print("[GitOps] Loaded local kubeconfig")
    except Exception:
        config.load_incluster_config()
        print("[GitOps] Loaded in-cluster kubeconfig")

    return client.CustomObjectsApi()
