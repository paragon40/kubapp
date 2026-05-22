resource "kubernetes_manifest" "alert_infra" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"

    metadata = {
      name      = "alert-infra"
      namespace = "monitoring"

      labels = {
        release = "kube-prometheus-stack"
        tier    = "infra"
      }
    }

    spec = {
      groups = [
        {
          name = "infra.rules"

          rules = [
            {
              alert = "NodeMemoryPressure"
              expr  = "node_memory_MemAvailable / node_memory_MemTotal < 0.1"
              for   = "5m"

              labels = {
                severity = "critical"
              }

              annotations = {
                summary = "Node memory pressure detected"
              }
            },

            {
              alert = "NodeDiskPressure"
              expr  = "node_filesystem_avail_bytes / node_filesystem_size_bytes < 0.1"
              for   = "5m"

              labels = {
                severity = "critical"
              }

              annotations = {
                summary = "Node disk pressure detected"
              }
            },

            {
              alert = "PodOOMKilled"
              expr  = "kube_pod_container_status_last_terminated_reason{reason=\"OOMKilled\"} == 1"
              for   = "1m"

              labels = {
                severity = "critical"
              }

              annotations = {
                summary = "Pod was OOMKilled"
              }
            }
          ]
        }
      ]
    }
  }

  depends_on = [
    helm_release.kube_prometheus_stack
  ]
}
