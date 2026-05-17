
resource "aws_eip" "sys_eip" {
  instance = aws_instance.sys_monitor.id
}

resource "aws_route53_record" "sys_monitor" {
  zone_id = var.zone_id
  name    = "sys-monitor.rundailytest.site"
  type    = "A"

  ttl = 300

  records = [aws_eip.sys_eip.public_ip]
}
