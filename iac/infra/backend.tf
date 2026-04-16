terraform {
  backend "s3" {
    bucket       = "kubapp-dev-state"
    key          = "dev/infra/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

