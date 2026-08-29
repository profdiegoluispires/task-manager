# Prometheus + Grafana (kube-prometheus-stack já traz dashboards de K8s prontos)
resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = true
  timeout          = 600

  set {
    name  = "grafana.service.type"
    value = "NodePort"
  }
  set {
    name  = "grafana.service.nodePort"
    value = "30090"
  }

  depends_on = [null_resource.k3d_cluster]
}

# Loki + Promtail (agregação e coleta de logs)
resource "helm_release" "loki_stack" {
  name             = "loki-stack"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "loki-stack"
  namespace        = "monitoring"
  create_namespace = true
  timeout          = 600

  set {
    name  = "grafana.enabled"
    value = "false" # já usamos o Grafana do kube-prometheus-stack
  }
  set {
    name  = "promtail.enabled"
    value = "true"
  }

  depends_on = [helm_release.kube_prometheus_stack]
}
