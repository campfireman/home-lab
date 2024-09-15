output "ingress_name" {
  value       = kubernetes_ingress_v1.ingress.metadata[0].name
  description = "Name of the created Ingress resource"
}

output "ingress_host" {
  value       = kubernetes_ingress_v1.ingress.spec[0].rule[0].host
  description = "Hostname of the Ingress"
}
