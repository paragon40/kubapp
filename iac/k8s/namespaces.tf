resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "kubernetes_namespace_v1" "ingress" {
  metadata {
    name = "ingress"
  }
}

resource "kubernetes_namespace_v1" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

resource "kubernetes_namespace_v1" "users" {
  metadata {
    name = "users"
  }
}

resource "kubernetes_namespace_v1" "admin" {
  metadata {
    name = "admin"
  }
}

