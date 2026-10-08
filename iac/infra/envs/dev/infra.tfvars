main_domain             = "rundailytest.online"
region                  = "us-east-1"
cluster_name            = "kubapp"
admin_kubapp            = "admin-timzapten"
admin_sys_monitor       = "admin-timzapnine"
admin_visitor           = "admin-timzapten"
admin_github            = "GitHubTerraformRole-dev"
database_role           = "db-terraform-role"
db_kubapp_reciever_role = "db-lets-kubapp-read-state-role"
cross_account_ids = {
  "monitor" = "704048935807"
  "db"      = "704048935807"
}

db_enabled = true
env        = "dev"

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
