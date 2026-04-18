variable "vpc_id" {
  type = string
}

variables "vpc_cidr" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "name_prefix" {
  type = string
}
