resource "kubernetes_namespace" "loki_namespace" {
  metadata {
    name = "loki"
  }
}

resource "helm_release" "loki_template" {
  name       = "loki"
  namespace  = kubernetes_namespace.loki_namespace.metadata.0.name
  repository = "https://grafana.github.io/helm-charts"

  chart = "loki-stack"

  values = [
    file("${path.module}/helm-values/loki.yaml")
  ]

}
