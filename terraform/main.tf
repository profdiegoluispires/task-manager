
# ==========================================================
# K3D
# ==========================================================

resource "null_resource" "k3d_cluster" {

  provisioner "local-exec" {
    command = "k3d cluster list | findstr task-manager >nul || k3d cluster create task-manager"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "k3d cluster delete task-manager"
  }
}

resource "null_resource" "k3d_grafana_port" {
  depends_on = [null_resource.k3d_cluster]

  triggers = {
    mapping = "30080:30080@loadbalancer-v2"
  }

  provisioner "local-exec" {
    command = "powershell -NoProfile -Command \"$$ports = docker port k3d-task-manager-serverlb 30080/tcp 2>$$null; if (-not ($$ports -match '30080')) { k3d cluster edit task-manager --port-add '30080:30080@loadbalancer' }\""
  }
}

# ==========================================================
# NAMESPACE DA APLICAÇÃO
# ==========================================================

resource "kubernetes_namespace" "task_manager" {
  depends_on = [null_resource.k3d_grafana_port]

  metadata {
    name = "task-manager"
  }
}

# ==========================================================
# NAMESPACE DE OBSERVABILIDADE
# ==========================================================

resource "kubernetes_namespace" "monitoring" {
  depends_on = [null_resource.k3d_grafana_port]

  metadata {
    name = "monitoring"
  }
}

# ==========================================================
# PROMETHEUS + GRAFANA
# ==========================================================

resource "helm_release" "kube_prometheus_stack" {
  depends_on = [kubernetes_namespace.monitoring]

  name      = "kube-prometheus-stack"
  namespace = "monitoring"

  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"

  timeout = 600
  wait    = false

  set = [
    {
      name  = "grafana.service.type"
      value = "NodePort"
    },
    {
      name  = "grafana.service.nodePort"
      value = "30080"
    },
    {
      name  = "prometheus.service.type"
      value = "NodePort"
    }
  ]
}

# ==========================================================
# LOKI + PROMTAIL
# ==========================================================

resource "helm_release" "loki_stack" {
  depends_on = [kubernetes_namespace.monitoring]

  name      = "loki"
  namespace = "monitoring"

  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki-stack"

  timeout = 600

  values = [
    yamlencode({
      grafana = {
        enabled = false
      }

      promtail = {
        enabled = true
      }

      loki = {
        enabled = true
      }
    })
  ]
}

# O loki-stack marca o datasource Loki como default por padrão.
# O kube-prometheus-stack já fornece o Prometheus como datasource default.
resource "kubernetes_config_map_v1_data" "loki_datasource" {
  depends_on = [helm_release.loki_stack]

  metadata {
    name      = "loki-loki-stack"
    namespace = "monitoring"
  }

  data = {
    "loki-stack-datasource.yaml" = <<-YAML
      apiVersion: 1
      datasources:
        - name: Loki
          type: loki
          access: proxy
          url: http://loki:3100
          version: 1
          isDefault: false
          jsonData: {}
    YAML
  }

  force = true
}

resource "null_resource" "restart_grafana" {
  depends_on = [kubernetes_config_map_v1_data.loki_datasource]

  triggers = {
    datasource = kubernetes_config_map_v1_data.loki_datasource.id
  }

  provisioner "local-exec" {
    command = "kubectl rollout restart deployment/kube-prometheus-stack-grafana -n monitoring"
  }
}

