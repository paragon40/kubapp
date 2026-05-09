resource "kubernetes_storage_class" "efs" {
  metadata {
    name = "efs-sc"
  }

  storage_provisioner = "efs.csi.aws.com"

  parameters = {
    provisioningMode = "efs-ap"
    fileSystemId     = local.efs_id
    directoryPerms   = "700"
    basePath         = "/dynamic_provisioning"

  }

  reclaim_policy         = "Retain"
  volume_binding_mode    = "Immediate"
  allow_volume_expansion = true
}

resource "aws_eks_addon" "efs_csi" {
  cluster_name             = var.cluster_name
  addon_name               = "aws-efs-csi-driver"
  addon_version            = data.aws_eks_addon_version.latest.version
  service_account_role_arn = local.efs_role_arn

  resolve_conflicts = "OVERWRITE"

  tags = local.k8s_labels
}
