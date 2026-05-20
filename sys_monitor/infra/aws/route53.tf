data "aws_route53_zone" "main" {
  name = var.domain_name
}

locals {
  subdomains = [
    "monitor",
    "app"
  ]
}

resource "aws_route53_record" "subdomains" {
  for_each = toset(local.subdomains)

  zone_id = data.aws_route53_zone.main.zone_id
  name    = "${each.key}.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = [aws_eip.sys_eip.public_ip]
}
