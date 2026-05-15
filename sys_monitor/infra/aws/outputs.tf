output "public_ip" {
  value = aws_instance.sys_monitor.public_ip
}

output "ssh_command" {
  value = "ssh ubuntu@${aws_instance.sys_monitor.public_ip}"
}

output "github_webhook_url" {
  value = "http://${aws_instance.sys_monitor.public_ip}:3000/webhook/github"
}

output "grafana_url" {
  value = "http://${aws_instance.sys_monitor.public_ip}:3001"
}

output "prometheus_url" {
  value = "http://${aws_instance.sys_monitor.public_ip}:9090"
}
