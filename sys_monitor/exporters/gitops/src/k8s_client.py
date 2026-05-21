from kubernetes import client, config
import os

def get_k8s_client():
    kubeconfig = os.getenv("KUBECONFIG", "/root/.kube/config")

    try:
        config.load_kube_config(config_file=kubeconfig)
        print("[GitOps] Loaded kubeconfig:", kubeconfig)
    except Exception as e:
        print("[GitOps] kubeconfig failed:", e)
        config.load_incluster_config()
        print("[GitOps] Loaded in-cluster config")

    return client.CustomObjectsApi()

