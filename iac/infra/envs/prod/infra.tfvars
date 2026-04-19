
CERT_ARN       = "arn:aws:acm:us-east-1:198200019771:certificate/a98757d4-69b3-4a6b-a01e-407622169dcc"
root_domain    = "rundailytest.site"
subdomain      = "kubapp"
region         = "us-east-1"
cluster_name   = "kubapp"
hosted_zone_id = "Z1031443294L16DYR25B4"

log_groups = {
  app_logs = {
    name      = "/kubapp/app-logs"
    retention = 1
  },
  audit_logs = {
    name      = "/kubapp/audit-logs"
    retention = 3
  },
  cluster_logs = {
    name      = "/aws/eks/kubapp/cluster"
    retention = 1
  }
}
