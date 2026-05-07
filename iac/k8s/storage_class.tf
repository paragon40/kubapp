resource "kubernetes_storage_class" "efs" {
  metadata {
    name = "efs-sc"
  }

  storage_provisioner = "efs.csi.aws.com"

  parameters = {
    provisioningMode = "efs-ap"
    fileSystemId     = local.efs_id
    directoryPerms   = "700"
  }

  reclaim_policy      = "Retain"
  volume_binding_mode = "Immediate"
}

