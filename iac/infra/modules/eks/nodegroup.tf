resource "aws_eks_node_group" "ec2_nodes" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.cluster_name}-ec2-nodes"
  node_role_arn   = var.node_role_arn

  subnet_ids = var.private_subnet_ids

  scaling_config {
    desired_size = var.node_desired_capacity
    max_size     = var.node_max_capacity
    min_size     = var.node_min_capacity
  }

  instance_types = [var.node_instance_type]

  ami_type  = "AL2_x86_64"
  disk_size = 30

  labels = {
    node_type = "admin"
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_eks_cluster.this
  ]

  tags = merge(var.tags, {
    name = "${var.cluster_name}-ec2-node"
    resource-type = "eks-node-group"
    eks-scope     = "node-group"
    node-type     = "ec2"
    node-group    = "primary"
    node-role     = "worker"
    workload     = "admin"
    eni-cluster = var.cluster_name
    eni-domain    = "compute"
    capacity-type = "on-demand"
  })
}
