resource "helm_release" "lb_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"

  values = [
    yamlencode({
      clusterName = local.cluster_name

      serviceAccount = {
        create = false
        name   = kubernetes_service_account_v1.lb_controller.metadata[0].name
      }

      region      = var.region
      vpcId       = local.vpc_id
      installCRDs = true
      podLabels   = local.k8s_labels
    })
  ]

  timeout         = 600
  wait            = true
  cleanup_on_fail = true

  depends_on = [
    null_resource.wait_for_active_eks,
    kubernetes_service_account_v1.lb_controller
  ]
}

resource "helm_release" "external_dns" {
  name      = "external-dns"
  namespace = "kube-system"

  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"

  set {
    name  = "provider"
    value = "aws"
  }

  set {
    name  = "policy"
    value = "upsert-only"
  }

  set {
    name  = "sources[0]"
    value = "ingress"
  }

  set {
    name  = "txtOwnerId"
    value = local.name_prefix
  }

  set {
    name  = "txtPrefix"
    value = "extdns-"
  }

  set {
    name  = "domainFilters[0]"
    value = var.domain
  }

  set {
    name  = "serviceAccount.create"
    value = "false"
  }

  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account_v1.external_dns.metadata[0].name
  }

  set {
    name  = "podLabels.plane"
    value = "k8s"
  }

  set {
    name  = "podLabels.project"
    value = var.project
  }

  set {
    name  = "podLabels.env"
    value = local.env
  }

  depends_on = [
    kubernetes_service_account_v1.external_dns,
    helm_release.lb_controller
  ]
}

resource "helm_release" "argocd" {
  name      = "argocd"
  namespace = kubernetes_namespace_v1.this["argocd"].metadata[0].name

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "6.7.0"

  create_namespace = true

  values = [
    yamlencode({
      global = {
        podLabels = local.k8s_labels
      }

      server = {
        service = {
          type = "ClusterIP"
        }
      }
    })
  ]

  timeout         = 2000
  wait            = true
  cleanup_on_fail = true

  depends_on = [
    kubernetes_namespace_v1.this["argocd"],
    helm_release.lb_controller,
    helm_release.fluentbit
  ]
}

resource "helm_release" "fluentbit" {
  name      = "fluent-bit"
  namespace = "kube-system"

  repository = "https://fluent.github.io/helm-charts"
  chart      = "fluent-bit"
  version    = "0.47.0"

  timeout         = 1200
  wait            = true
  cleanup_on_fail = true

  values = [
    yamlencode({

      serviceAccount = {
        create = false
        name   = "fluent-bit"
      }

      nodeSelector = {
        "eks.amazonaws.com/compute-type" = "ec2"
      }

      podLabels = local.logs_labels

      config = {

        service = <<-EOF
          [SERVICE]
              Flush         1
              Daemon        Off
              Log_Level     info
              Parsers_File  parsers.conf
        EOF

        inputs = <<-EOF
          [INPUT]
              Name              tail
              Path              /var/log/containers/*.log
              Parser            cri
              Tag               kube.*
              Refresh_Interval  5
              Mem_Buf_Limit     50MB
              Skip_Long_Lines   On
        EOF

        filters = <<-EOF
          [FILTER]
              Name                kubernetes
              Match               kube.*
              Merge_Log           On
              Keep_Log            Off
              K8S-Logging.Parser  On
              K8S-Logging.Exclude Off
        EOF

        outputs = <<-EOF
          [OUTPUT]
              Name                cloudwatch_logs
              Match               kube.*
              region              ${var.region}
              log_group_name      ${local.app_logs}
              log_stream_prefix   kubernetes-
              auto_create_group   true
        EOF
      }
    })
  ]

  depends_on = [
    aws_eks_addon.efs_csi,
    null_resource.wait_for_lb_webhook,
    kubernetes_service_account_v1.fluentbit
  ]
}


resource "helm_release" "kube_prometheus_stack" {
  name      = "kube-prometheus-stack"
  namespace = kubernetes_namespace_v1.this["monitoring"].metadata[0].name

  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "58.0.0"

  timeout         = 2000
  wait            = true
  cleanup_on_fail = true

  values = [
    yamlencode({

      global = {
        podLabels = local.monitoring_labels
      }

      # GRAFANA
      grafana = {
        initChownData = {
          enabled = false
        }

        admin = {
          existingSecret = "grafana-admin"
          userKey        = "admin-user"
          passwordKey    = "admin-password"
        }

        "grafana.ini" = {
          "auth.anonymous" = {
            enabled  = true
            org_role = "Admin"
          }
        }

        service = {
          type = "LoadBalancer"
        }

        persistence = {
          enabled          = true
          storageClassName = kubernetes_storage_class.efs.metadata[0].name
          accessModes      = ["ReadWriteMany"]
          size             = "10Gi"
        }

        podLabels = local.monitoring_labels
      }

      # PROMETHEUS
      ############################
      prometheus = {
        prometheusSpec = {

          # HOW LONG METRICS LIVE
          retention = "7d"

          # HARD DISK LIMIT SAFETY NET
          retentionSize = "15GB"

          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = kubernetes_storage_class.efs.metadata[0].name
                accessModes      = ["ReadWriteMany"]

                resources = {
                  requests = {
                    storage = "20Gi"
                  }
                }
              }
            }
          }

          podMetadata = {
            labels = local.monitoring_labels
          }
        }
      }

      # ALERTMANAGER
      alertmanager = {
        alertmanagerSpec = {

          retention = "120h"

          storage = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = kubernetes_storage_class.efs.metadata[0].name
                accessModes      = ["ReadWriteMany"]

                resources = {
                  requests = {
                    storage = "5Gi"
                  }
                }
              }
            }
          }

          podMetadata = {
            labels = local.monitoring_labels
          }
        }
      }

      # NODE SELECTION
      nodeSelector = {
        "eks.amazonaws.com/compute-type" = "ec2"
      }
    })
  ]

  depends_on = [
    aws_eks_addon.efs_csi,
    helm_release.fluentbit,
    helm_release.argocd,
    kubernetes_namespace_v1.this["monitoring"]
  ]
}


