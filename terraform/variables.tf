variable "cluster_name" {
  description = "Nome do cluster k3d"
  type        = string
  default     = "task-manager"
}

variable "server_count" {
  description = "Quantidade de servidores do k3d"
  type        = number
  default     = 1
}

variable "agent_count" {
  description = "Quantidade de agentes do k3d"
  type        = number
  default     = 1
}