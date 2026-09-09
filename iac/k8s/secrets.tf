resource "null_resource" "grafana_admin_secret" {
  triggers = {
    secret_file = filesha256(var.secret_file)
  }

  provisioner "local-exec" {
    command = "${path.module}/secrets.sh ${var.secret_file}"
  }

  depends_on = [
    kubernetes_namespace_v1.this["monitoring"]
  ]
}
