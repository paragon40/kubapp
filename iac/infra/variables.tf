
variable "region" {
  type = string
}

variable "kubernetes_v" {
  type    = string
  default = "1.31"
}

variable "CERT_ARN" {
  type = string
}

variable "root_domain" {
  type = string
}

variable "subdomain" {
  type    = string
  default = "kubapp"
}

variable "cluster_name" {
  type    = string
  default = "kubapp"
}

variable "hosted_zone_id" {
  type = string
}

variable "log_groups" {
  type = map(object({
    name      = string
    retention = number
  }))
}
