from kubernetes import client, config
import os

def get_k8s_client():
    kubeconfig = os.getenv("KUBECONFIG", "/root/.kube/config")

    try:
        config.load_kube_config(config_file=kubeconfig)
        print(f"[GitOps] Loaded kubeconfig: {kubeconfig}")
    except Exception as e:
        print(f"[GitOps] kubeconfig failed: {e}")
        raise

    api_client = client.ApiClient()

    return {
        "custom": client.CustomObjectsApi(api_client),
        "core": client.CoreV1Api(api_client)
    }
