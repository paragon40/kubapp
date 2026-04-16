variable "name" {
  type    = string
  default = "kubapp"
}

variable "tags" {
  type    = map(string)
  default = {}
}
