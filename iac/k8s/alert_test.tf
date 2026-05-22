resource "kubernetes_manifest" "alert_test" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"

    metadata = {
      name      = "alert-test"
      namespace = "monitoring"

      labels = {
        release = "kube-prometheus-stack"
        tier    = "testing"
        domain  = "slo"
      }
    }

    spec = {
      groups = [
        {
          name = "test.rules"

          rules = [
            {
              alert = "TestAlertAlwaysFiring"

              expr = "vector(1)"

              for = "0m"

              labels = {
                severity = "warning"
                tier     = "test"
              }

              annotations = {
                summary     = "TEST ALERT: This alert always fires"
                description = "Used to verify Alertmanager routing and notification delivery"
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
