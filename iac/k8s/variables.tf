variable "region" {
  type = string
}

variable "cert_arn" {
  type = string
}

variable "domain" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "DOCKER_PASSWORD" {
  type      = string
  sensitive = true
}

variable "DOCKER_USERNAME" {
  type      = string
  sensitive = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
