# ---------- ConfigMap ----------
resource "kubernetes_config_map" "task_manager_config" {
  metadata {
    name = "task-manager-config"
  }
  data = {
    DATABASE_HOST     = "postgres-service"
    DATABASE_PORT     = "5432"
    DATABASE_NAME     = "task_manager"
    DATABASE_USER     = "admin"
    DATABASE_PASSWORD = "admin"
    PORT              = "3000"
  }
  depends_on = [null_resource.k3d_cluster]
}

# ---------- Postgres ----------
resource "kubernetes_deployment" "postgres" {
  metadata {
    name = "postgres"
  }
  spec {
    replicas = 1
    selector {
      match_labels = { app = "postgres" }
    }
    template {
      metadata {
        labels = { app = "postgres" }
      }
      spec {
        container {
          name  = "postgres"
          image = "postgres:15"
          port {
            container_port = 5432
          }
          env_from {
            config_map_ref {
              name = kubernetes_config_map.task_manager_config.metadata[0].name
            }
          }
          env {
            name  = "POSTGRES_USER"
            value = "admin"
          }
          env {
            name  = "POSTGRES_PASSWORD"
            value = "admin"
          }
          env {
            name  = "POSTGRES_DB"
            value = "task_manager"
          }
        }
      }
    }
  }
  depends_on = [kubernetes_config_map.task_manager_config]
}

resource "kubernetes_service" "postgres" {
  metadata {
    name = "postgres-service"
  }
  spec {
    selector = { app = "postgres" }
    port {
      port        = 5432
      target_port = 5432
    }
  }
}

# ---------- task-manager ----------
resource "kubernetes_deployment" "task_manager" {
  metadata {
    name = "task-manager"
  }
  spec {
    replicas = 3
    selector {
      match_labels = { app = "task-manager" }
    }
    template {
      metadata {
        labels = { app = "task-manager" }
      }
      spec {
        container {
          name              = "task-manager"
          image             = var.app_image
          image_pull_policy = "IfNotPresent"
          port {
            container_port = 3000
          }
          env_from {
            config_map_ref {
              name = kubernetes_config_map.task_manager_config.metadata[0].name
            }
          }
        }
      }
    }
  }
  depends_on = [kubernetes_deployment.postgres]
}

resource "kubernetes_service" "task_manager" {
  metadata {
    name = "task-manager-service"
  }
  spec {
    type     = "NodePort"
    selector = { app = "task-manager" }
    port {
      port        = 3000
      target_port = 3000
      node_port   = 30080
    }
  }
}
