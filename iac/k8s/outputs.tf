
output "namespaces" {
  value = [
    for ns in kubernetes_namespace_v1.this : ns.metadata[0].name
  ]
}

output "cluster_name" {
  value = local.cluster_name
}

output "Environment" {
  value = local.env
}
