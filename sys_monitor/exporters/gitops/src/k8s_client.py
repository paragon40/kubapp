from kubernetes import client, config
import os

def get_k8s_client():

    kubeconfig_path = os.getenv("KUBECONFIG", "/root/.kube/config")
    config.load_kube_config(config_file=kubeconfig_path)

    api_client = client.ApiClient()

    return {
        "custom": client.CustomObjectsApi(api_client),
        "core": client.CoreV1Api(api_client)
    }
