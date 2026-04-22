resource "aws_ecr_repository" "kubapp" {
  for_each = var.repositories

  name = "${var.name_prefix}-${each.value}"

  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(var.tags, {
    name = "${var.name_prefix}-${each.value}"
    resource-type = "ecr-repository"
    layer         = "artifact-registry"
    cluster       = var.cluster_name
    eni-cluster   = var.cluster_name
    repo-name     = each.value
    workload-type = each.value
  })
}

resource "aws_ecr_lifecycle_policy" "kubapp" {
  for_each = aws_ecr_repository.kubapp

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

