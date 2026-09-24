main_domain    = "rundailytest.online"
region         = "us-east-1"
cluster_name   = "kubapp"
admin_arn      = "arn:aws:iam::259183055744:user/admin-timzapten"
access_iam_arn = "arn:aws:iam::259183055744:role/GitHubTerraformRole-dev"
account_id     = "259183055744"
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
