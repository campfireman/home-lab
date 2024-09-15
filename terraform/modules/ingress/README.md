# Ingress Module

This module creates a Kubernetes Ingress resource with Traefik as the ingress controller and configurable TLS settings.

## Inputs

| Name                   | Description                                               | Type          | Default | Required |
| ---------------------- | --------------------------------------------------------- | ------------- | ------- | :------: |
| name                   | Name of the Ingress resource                              | `string`      | n/a     |   yes    |
| namespace              | Namespace for the Ingress resource                        | `string`      | n/a     |   yes    |
| host                   | Hostname for the Ingress                                  | `string`      | n/a     |   yes    |
| service_name           | Name of the backend service                               | `string`      | n/a     |   yes    |
| service_port           | Port of the backend service                               | `number`      | n/a     |   yes    |
| tls_config             | TLS configuration type (NO_TLS, INTERNAL_TLS, PUBLIC_TLS) | `string`      | n/a     |   yes    |
| tls_secret_name        | Name of the TLS secret                                    | `string`      | `""`    |    no    |
| additional_annotations | Additional annotations to add to the Ingress              | `map(string)` | `{}`    |    no    |

## Outputs

| Name         | Description                          |
| ------------ | ------------------------------------ |
| ingress_name | Name of the created Ingress resource |
| ingress_host | Hostname of the Ingress              |

## Usage

```hcl
module "my_ingress" {
  source = "./modules/ingress"

  name            = "my-app-ingress"
  namespace       = "my-namespace"
  host            = "myapp.example.com"
  service_name    = "my-app-service"
  service_port    = 80
  tls_config      = "INTERNAL_TLS"
  tls_secret_name = "my-app-tls"
}
```
