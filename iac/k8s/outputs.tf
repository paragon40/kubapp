
output "user_namespace" {
  value = kubernetes_namespace_v1.this["users"].metadata[0].name
}

output "cluster_name" {
  value = local.cluster_name
}

output "Environment" {
  value = local.env
}
