resource "kubernetes_storage_class" "efs" {
  metadata {
    name = "efs-sc"
  }

  storage_provisioner = "efs.csi.aws.com"

  parameters = {
    provisioningMode = "efs-ap"
    fileSystemId     = local.efs_id

    directoryPerms = "700"

    basePath = "/dynamic_provisioning"

    gidRangeStart = "1000"
    gidRangeEnd   = "2000"

    ensureUniqueDirectory = "true"
  }

  reclaim_policy      = "Retain"
  volume_binding_mode = "Immediate"
}
