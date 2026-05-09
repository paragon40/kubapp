resource "aws_efs_access_point" "grafana" {
  file_system_id = aws_efs_file_system.this.id

  posix_user {
    uid = 472
    gid = 472
  }

  root_directory {
    path = "/grafana"
    creation_info {
      owner_uid   = 472
      owner_gid   = 472
      permissions = "0775"
    }
  }
}
