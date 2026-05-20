output "public_ip" {
  value = aws_eip.sys_eip.public_ip
}

output "ssh_command" {
  value = "ssh ubuntu@${aws_eip.sys_eip.public_ip}"
}


output "grafana_url" {
  value = "http://monitor.${var.domain_name}:3001"
}

output "prometheus_url" {
  value = "http://monitor.${var.domain_name}:9090"
}

output "github_metrics_url" {
  value = "http://app.${var.domain_name}:3000/metrics"
}

output "github_url" {
  value = "http://app.${var.domain_name}:3000"
}
