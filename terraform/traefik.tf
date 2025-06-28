resource "kubernetes_manifest" "traefik_config" {
  manifest = {
    apiVersion = "helm.cattle.io/v1"
    kind       = "HelmChartConfig"
    metadata = {
      name      = "traefik"
      namespace = "kube-system"
    }
    spec = {
      valuesContent = <<-YAML
        dashboard:
          enabled: true
        additionalArguments:
          - "--entryPoints.mqtt.address=:1883/tcp"
        ports:
            mqtt:
                port: 1883
                expose:
                  enabled: true
                exposedPort: 1883
                protocol: TCP
                YAML
    }
  }
}

# kubectl patch svc traefik -n kube-system --type='merge' -p '{
#   "spec": {
#     "ports": [
#       {"name":"mqtt","port":1883,"protocol":"TCP"}
#     ]
#   }
# }'
