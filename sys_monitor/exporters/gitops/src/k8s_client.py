from kubernetes import client
import boto3
import os
import base64
import threading
from functools import lru_cache


class K8sClientFactory:
    """
    Singleton-style EKS Kubernetes client.
    - caches cluster metadata
    """

    _lock = threading.Lock()
    _api_client = None
    _custom = None
    _core = None

    @classmethod
    def _fetch_cluster_info(cls):
        cluster_name = os.getenv("TARGET_CLUSTER_NAME", "kubapp-dev")
        region = os.getenv("TARGET_REGION", "us-east-1")

        eks = boto3.client("eks", region_name=region)

        cluster = eks.describe_cluster(name=cluster_name)["cluster"]

        return {
            "endpoint": cluster["endpoint"],
            "ca": cluster["certificateAuthority"]["data"]
        }

    @classmethod
    def _build_client(cls):
        cluster_name = os.getenv("TARGET_CLUSTER_NAME", "kubapp-dev")
        region = os.getenv("TARGET_REGION", "us-east-1")

        eks = boto3.client("eks", region_name=region)

        # cache cluster info
        info = cls._fetch_cluster_info()

        # generate token
        token = eks.get_token(clusterName=cluster_name)["status"]["token"]

        # build config
        configuration = client.Configuration()
        configuration.host = info["endpoint"]
        configuration.verify_ssl = True

        # decode CA ONCE (in-memory, no /tmp file)
        ca_cert = base64.b64decode(info["ca"])
        configuration.ssl_ca_cert = "/dev/stdin"

        # write once in memory temp object
        import tempfile
        ca_file = tempfile.NamedTemporaryFile(delete=False)
        ca_file.write(ca_cert)
        ca_file.flush()

        configuration.ssl_ca_cert = ca_file.name

        configuration.api_key = {
            "authorization": f"Bearer {token}"
        }

        api_client = client.ApiClient(configuration)

        cls._api_client = api_client
        cls._custom = client.CustomObjectsApi(api_client)
        cls._core = client.CoreV1Api(api_client)

    @classmethod
    def get_clients(cls):
        if cls._api_client:
            return {
                "custom": cls._custom,
                "core": cls._core
            }

        with cls._lock:
            if not cls._api_client:
                cls._build_client()

        return {
            "custom": cls._custom,
            "core": cls._core
        }
