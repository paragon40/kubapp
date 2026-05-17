output "public_ip" {
  value = aws_eip.sys_eip.public_ip
}

output "ssh_command" {
  value = "ssh ubuntu@${aws_eip.sys_eip.public_ip}"
}


output "grafana_url" {
  value = "http://grafana.${var.domain_name}:3001"
}

output "prometheus_url" {
  value = "http://prom.${var.domain_name}:9090"
}

output "metrics_url" {
  value = "http://metrics.${var.domain_name}:3000/metrics"
}

output "github_url" {
  value = "http://github.${var.domain_name}:3000"
}
