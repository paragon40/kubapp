locals {
  name_prefix  = "${var.project}-${var.env}"
  cluster_name = "${var.cluster_name}-${var.env}"

  full_domain = (var.env == "prod"
    ? "${var.subdomain}.${var.root_domain}"
    : "${var.env}.${var.subdomain}.${var.root_domain}"
  )

  main_domain = var.main_domain

  # GLOBAL TRACE ID 
  trace_id = "${var.project}-${var.env}-${local.cluster_name}"

  base_tags = {
    project = var.project
    env     = var.env
    cluster = local.cluster_name

    trace-id   = local.trace_id
    plane      = "infra"
    owner      = "platform"
    managed-by = "terraform"
  }

  common_tags = local.base_tags

  # ----------------------------
  # App log groups (custom)
  # ----------------------------
  app_log_groups = {
    app_logs = {
      name      = "/${var.project}/${var.env}/app-logs"
      retention = var.log_groups.app_logs.retention
      log_type  = "application"
      scope     = "workload"
    }

    audit_logs = {
      name      = "/${var.project}/${var.env}/audit-logs"
      retention = var.log_groups.audit_logs.retention
      log_type  = "security"
      scope     = "system"
    }

    # ----------------------------
    # EKS system log group
    # ----------------------------
    eks_cluster_log_group = {
      name      = "/aws/eks/${local.cluster_name}/cluster"
      retention = var.log_groups.cluster_logs.retention
      log_type  = "eks"
      scope     = "cluster"
    }

    vpc_flow_log = {
      name      = "/aws/vpc/${local.cluster_name}-flowlogs"
      retention = var.log_groups.vpc_logs.retention
      log_type  = "network"
      scope     = "network"
    }
  }
  efs_access_points = {
    user = {
      path = "/user-app"
      uid  = 1000
      gid  = 1000
    }

    admin = {
      path = "/admin-app"
      uid  = 1001
      gid  = 1001
    }

    monitoring = {
      path = "/monitoring-app"
      uid  = 1002
      gid  = 1002
    }
  }
}

