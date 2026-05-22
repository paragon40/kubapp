resource "kubernetes_manifest" "alert_app" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"

    metadata = {
      name      = "alert-app"
      namespace = "monitoring"

      labels = {
        release = "kube-prometheus-stack"
        tier    = "app"
      }
    }

    spec = {
      groups = [
        {
          name = "app.rules"

          rules = [
            {
              alert = "PodCrashLooping"
              expr  = "increase(kube_pod_container_status_restarts_total[10m]) > 3"
              for   = "5m"

              labels = {
                severity = "warning"
              }

              annotations = {
                summary = "Pod crash looping detected"
              }
            },

            {
              alert = "DeploymentUnavailable"
              expr  = "kube_deployment_status_replicas_available < kube_deployment_spec_replicas"
              for   = "5m"

              labels = {
                severity = "critical"
              }

              annotations = {
                summary = "Deployment not fully available"
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
