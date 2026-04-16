
output "namespace" {
  value = kubernetes_namespace_v1.users.metadata[0].name
}
