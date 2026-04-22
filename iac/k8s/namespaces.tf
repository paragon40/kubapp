resource "kubernetes_namespace_v1" "this" {
  for_each = local.namespaces

  metadata {
    name = each.key

    labels = merge(
      local.k8s_labels,
      each.value,
      {
        namespace = each.key
      }
    )
  }
}
