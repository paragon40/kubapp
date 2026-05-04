resource "aws_route53_zone" "kubapp" {
  name = var.domain
  depends_on = [
    null_resource.mark_cluster_ready
  ]
}

resource "aws_route53_record" "root" {
  zone_id = aws_route53_zone.kubapp.zone_id
  name    = var.domain
  type    = "A"

  alias {
    name                   = aws_lb.ingress.dns_name
    zone_id                = aws_lb.ingress.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "apps" {
  for_each = toset(["user", "admin", "weather"])

  zone_id = aws_route53_zone.kubapp.zone_id
  name    = "${each.key}.${var.domain}"
  type    = "CNAME"
  ttl     = 60

  records = [aws_lb.ingress.dns_name]
}


