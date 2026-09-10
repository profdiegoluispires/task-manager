resource "google_artifact_registry_repository" "repo" {
  location      = "us-central1"
  repository_id = "task-manager-repo"
  format        = "DOCKER"
  project       = "residencia-tech-gcp"
}

resource "google_cloud_run_v2_service" "task_manager" {
  name     = "task-manager"
  location = "us-central1"
  project  = "residencia-tech-gcp"
  deletion_protection=false

  template {
    # Necessário para suportar múltiplos containers (sidecar) na mesma revisão.
    execution_environment = "EXECUTION_ENVIRONMENT_GEN2"

    containers {
      name = "app"
      # imagem publicada no Passo 2, via scripts/deploy-container.sh
      image = "us-central1-docker.pkg.dev/residencia-tech-gcp/task-manager-repo/task-manager:latest"
      ports { container_port = 3000 }

      # Mesmas variáveis do serviço "app" no docker-compose.yml, apontando
      # para o container "postgres" ao lado (acessível via localhost no Cloud Run).
      env {
        name  = "DATABASE_HOST"
        value = "localhost"
      }
      env {
        name  = "DATABASE_PORT"
        value = "5432"
      }
      env {
        name  = "DATABASE_NAME"
        value = "task_manager"
      }
      env {
        name  = "DATABASE_USER"
        value = "admin"
      }
      env {
        name  = "DATABASE_PASSWORD"
        value = "admin"
      }

      # Só sobe depois que o postgres responder na porta 5432.
      depends_on = ["postgres"]
    }

    containers {
      name  = "postgres"
      # Mesma imagem e credenciais do serviço "postgres" no docker-compose.yml.
      image = "postgres:15"

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

      volume_mounts {
        name       = "postgres-data"
        mount_path = "/var/lib/postgresql/data"
      }

      startup_probe {
        tcp_socket { port = 5432 }
        initial_delay_seconds = 5
        period_seconds        = 3
        failure_threshold     = 10
      }

      # Sidecars só recebem CPU durante requisições por padrão; o Postgres
      # precisa de CPU constante para não cair entre uma requisição e outra.
      resources {
        cpu_idle = false
      }
    }

    # Volume em memória: os dados do Postgres NÃO persistem entre revisões/restarts.
    # Para persistência real, migrar para Cloud SQL.
    volumes {
      name = "postgres-data"
      empty_dir {
        medium     = "MEMORY"
        size_limit = "256Mi"
      }
    }
  }
}

resource "google_cloud_run_v2_service_iam_member" "public" {
  name     = google_cloud_run_v2_service.task_manager.name
  location = google_cloud_run_v2_service.task_manager.location
  role     = "roles/run.invoker"
  member   = "allUsers"
  project  = "residencia-tech-gcp"
}