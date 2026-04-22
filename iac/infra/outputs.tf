
output "lb_controller_role_arn" {
  value = module.iam_irsa.lb_controller_role_arn
}

output "fluentbit_role_arn" {
  value = module.iam_irsa.fluentbit_role_arn
}

output "efs_role_arn" {
  value = module.iam_irsa.efs_role_arn
}

output "efs_id" {
  value = module.efs.efs_id
}

output "efs_dns_name" {
  value = module.efs.efs_dns_name
}

output "efs_security_group_id" {
  value = module.efs.efs_security_group_id
}

output "efs_user_app_ap_id" {
  value = module.efs.efs_access_points["user"].id
}

output "efs_admin_app_ap_id" {
  value = module.efs.efs_access_points["admin"].id
}

output "efs_monitoring_app_ap_id" {
  value = module.efs.efs_access_points["monitoring"].id
}

output "efs_access_point_arns" {
  value = {
    for k, v in module.efs.efs_access_points : k => v.arn
  }
}

output "vpc_id" {
  value = module.network.vpc_id
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_ca_certificate" {
  value = module.eks.cluster_ca_certificate
}

output "log_group_names" {
  value = module.logging.log_group_names
}

output "external_dns_role_arn" {
  value = module.iam_irsa.external_dns_role_arn
}

output "domain" {
  value = "${var.subdomain}.${var.root_domain}"
}

output "cert_arn" {
  value = var.CERT_ARN
}

output "env" {
  value = var.env
}

output "project" {
  value = var.project
}

output "name_prefix" {
  value = local.name_prefix
}

output "common_tags" {
  value = local.common_tags
}

output "full_domain" {
  value = local.full_domain
}

