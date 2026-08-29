variable "cluster_name" {
  description = "Nome do cluster k3d"
  type        = string
  default     = "task-cluster"
}

variable "app_image" {
  description = "Imagem Docker do task-manager"
  type        = string
  default     = "task-manager:latest"
}
