
CERT_ARN       = "arn:aws:acm:eu-north-1:532918215760:certificate/7bca1b4c-8d33-4234-b1ff-25b2ae416300"
main_domain    = "rundailytest.online"
region         = "us-east-1"
cluster_name   = "kubapp"
admin_arn      = "arn:aws:iam::532918215760:user/admin-timzap"
access_iam_arn = "arn:aws:iam::532918215760:role/GitHubTerraformRole-dev"
account_id     = "532918215760"
env            = "dev"

log_groups = {
  app_logs = {
    retention = 1
  },
  audit_logs = {
    retention = 3
  },
  cluster_logs = {
    retention = 1
  },
  vpc_logs = {
    retention = 1
  }
}
