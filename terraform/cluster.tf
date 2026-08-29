# Cria o cluster k3d local via local-exec, expondo:
# - 8080 -> app task-manager (NodePort 30080)
# - 3001 -> Grafana (NodePort 30090)
resource "null_resource" "k3d_cluster" {
  triggers = {
    cluster_name = var.cluster_name
  }

  provisioner "local-exec" {
    command = "k3d cluster create ${var.cluster_name} -p 8080:30080@loadbalancer -p 3001:30090@loadbalancer --wait"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "k3d cluster delete ${self.triggers.cluster_name}"
  }
}
