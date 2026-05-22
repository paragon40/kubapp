resource "kubernetes_manifest" "alert_ingress" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"

    metadata = {
      name      = "alert-ingress"
      namespace = "monitoring"

      labels = {
        release = "kube-prometheus-stack"
        tier    = "ingress"
      }
    }

    spec = {
      groups = [
        {
          name = "ingress.rules"

          rules = [
            {
              alert = "HighHTTP5xxRate"

              expr = <<EOT
sum(rate(nginx_ingress_controller_requests{status=~"5.."}[5m]))
/
sum(rate(nginx_ingress_controller_requests[5m])) > 0.05
EOT

              for = "5m"

              labels = {
                severity = "critical"
              }

              annotations = {
                summary = "High HTTP 5xx error rate detected"
              }
            },

            {
              alert = "NoTrafficDetected"
              expr  = "sum(rate(nginx_ingress_controller_requests[5m])) == 0"
              for   = "10m"

              labels = {
                severity = "warning"
              }

              annotations = {
                summary = "No traffic detected on ingress"
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
