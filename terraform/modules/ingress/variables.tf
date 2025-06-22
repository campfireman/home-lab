variable "name" {
  type        = string
  description = "Name of the Ingress resource"
}

variable "namespace" {
  type        = string
  description = "Namespace for the Ingress resource"
}

variable "host" {
  type        = string
  description = "Hostname for the Ingress"
}

variable "service_name" {
  type        = string
  description = "Name of the backend service"
}

variable "service_port" {
  type        = number
  description = "Port of the backend service"
}

variable "tls_config" {
  type        = string
  description = "TLS configuration type"
  validation {
    condition     = contains(["NO_TLS", "INTERNAL_TLS", "PUBLIC_TLS"], var.tls_config)
    error_message = "Valid values for tls_config are: NO_TLS, INTERNAL_TLS, PUBLIC_TLS."
  }
}

variable "tls_secret_name" {
  type        = string
  description = "Name of the TLS secret"
  default     = ""
}

variable "additional_annotations" {
  type        = map(string)
  description = "Additional annotations to add to the Ingress"
  default     = {}
}

variable "dns_target_ip" {
  type        = string
  description = "The IP address the DNS record should point to."
}
