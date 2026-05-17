output "public_ip" {
  value = aws_eip.sys_eip.public_ip
}

output "ssh_command" {
  value = "ssh ubuntu@${aws_eip.sys_eip.public_ip}"
}

output "github_webhook_url" {
  value = "https://${aws_eip.sys_eip.public_ip}:3000/webhook/github"
}

output "grafana_url" {
  value = "https://${aws_eip.sys_eip.public_ip}:3001"
}

output "prometheus_url" {
  value = "https://${aws_eip.sys_eip.public_ip}:9090"
}
