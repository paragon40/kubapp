terraform {
  backend "s3" {
    bucket = "kubapp-dev-state"
    key    = "dev/k8s/terraform.tfstate"
    region = "us-east-1"
    #dynamodb_table = "kubapp-dev-db"
    use_lockfile = true
    encrypt      = true
  }
}
