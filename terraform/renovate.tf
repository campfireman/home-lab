locals {
  renovate_name    = "renovate"
  renovate_version = "43.281.0"
}

resource "kubernetes_namespace_v1" "renovate_namespace" {
  metadata {
    name = local.renovate_name
  }
}

resource "kubernetes_secret_v1" "renovate_secrets" {
  metadata {
    name      = "${local.renovate_name}-secrets"
    namespace = kubernetes_namespace_v1.renovate_namespace.metadata.0.name
  }
  data = {
    RENOVATE_TOKEN = data.sops_file.secrets.data["renovate_gitlab_token"]
    # Read-only/no-scope GitHub PAT — only used for release-notes lookups and
    # resolving GitHub-hosted deps (e.g. hashicorp/terraform), not GitLab
    # auth. GITHUB_COM_TOKEN is a Renovate-recognized env var name, distinct
    # from the RENOVATE_*-prefixed config options.
    GITHUB_COM_TOKEN = data.sops_file.secrets.data["renovate_github_token"]
  }
}

# The cluster's internal-issuer root CA (cert-manager's cert-manager/internal-ca
# secret) — the same CA that signs every INTERNAL_TLS ingress in this repo,
# including registry.home.arpa's. Renovate's Node.js runtime doesn't trust it
# by default, which breaks docker datasource lookups against
# registry.home.arpa with UNABLE_TO_VERIFY_LEAF_SIGNATURE. This is the public
# cert only (no key) — not secret material, so a ConfigMap is appropriate
# rather than a sops-sourced Secret.
resource "kubernetes_config_map_v1" "renovate_internal_ca" {
  metadata {
    name      = "${local.renovate_name}-internal-ca"
    namespace = kubernetes_namespace_v1.renovate_namespace.metadata.0.name
  }
  data = {
    "internal-ca.pem" = <<-EOT
      -----BEGIN CERTIFICATE-----
      MIICjDCCAhKgAwIBAgIUJUMXJ4pmlhpSg/7GMkq0YoJr/AcwCgYIKoZIzj0EAwIw
      fTELMAkGA1UEBhMCREUxDDAKBgNVBAgMA0hBTTEMMAoGA1UEBwwDSEFNMQ4wDAYD
      VQQKDAV0X25ldDELMAkGA1UECwwCSVQxFjAUBgNVBAMMDVR1cmUgQ2xhdXNzZW4x
      HTAbBgkqhkiG9w0BCQEWDmFkbWluQHR1cmUuZGV2MB4XDTIzMDYyNzA4Mzc0N1oX
      DTMzMDYyNDA4Mzc0N1owfTELMAkGA1UEBhMCREUxDDAKBgNVBAgMA0hBTTEMMAoG
      A1UEBwwDSEFNMQ4wDAYDVQQKDAV0X25ldDELMAkGA1UECwwCSVQxFjAUBgNVBAMM
      DVR1cmUgQ2xhdXNzZW4xHTAbBgkqhkiG9w0BCQEWDmFkbWluQHR1cmUuZGV2MHYw
      EAYHKoZIzj0CAQYFK4EEACIDYgAElQTGRRskNUi+ojjJHCcmcFTN7zl1qqHsnIlI
      LDJJLK5kM9PJdZCe4Ebvtz6SKPj1WiPgJ6hWcPbOFJyokUpDHYb4HfHqrcGCD87q
      87CZnY1MUpFH1Cxy8fCpdj9Iern4o1MwUTAdBgNVHQ4EFgQU4ZIfpfVYB0DrWBPZ
      wBTTpxHvCaswHwYDVR0jBBgwFoAU4ZIfpfVYB0DrWBPZwBTTpxHvCaswDwYDVR0T
      AQH/BAUwAwEB/zAKBggqhkjOPQQDAgNoADBlAjEAp3N//h2LlYme1UL1sIaU2Lat
      6ArETULdXWIgzRlH/LK3+1tKovTeP7MfQ5Bel54HAjAcvwP88+mDnCqR1krpoysW
      S3k2AWMMEkk1Bdr7J2yEhXF1+7i5GUZS1vdIXj1NM4Y=
      -----END CERTIFICATE-----
    EOT
  }
}

# Renovate has to run in-cluster rather than as a GitLab CI job: it needs the
# docker datasource to resolve tags from registry.home.arpa, which only
# resolves/routes on the home LAN — the same reason go-tube's own pipeline
# pins its build/gate/publish jobs to the home-lab runner (see
# gitlab_runner.tf). A CronJob mirrors postgres.tf's postgres_backup, the
# only existing periodic-job precedent in this repo.
resource "kubernetes_cron_job_v1" "renovate" {
  metadata {
    name      = local.renovate_name
    namespace = kubernetes_namespace_v1.renovate_namespace.metadata.0.name
  }

  spec {
    schedule                      = "0 */4 * * *"
    concurrency_policy            = "Forbid"
    successful_jobs_history_limit = 3
    failed_jobs_history_limit     = 3

    job_template {
      metadata {
        name      = local.renovate_name
        namespace = kubernetes_namespace_v1.renovate_namespace.metadata.0.name
      }
      spec {
        template {
          metadata {
            name = local.renovate_name
            labels = {
              app = local.renovate_name
            }
          }

          spec {
            restart_policy = "OnFailure"

            container {
              name  = local.renovate_name
              image = "renovate/renovate:${local.renovate_version}"

              env_from {
                secret_ref {
                  name     = kubernetes_secret_v1.renovate_secrets.metadata.0.name
                  optional = false
                }
              }

              env {
                name  = "RENOVATE_PLATFORM"
                value = "gitlab"
              }
              env {
                name  = "RENOVATE_ENDPOINT"
                value = "https://gitlab.com/api/v4"
              }
              env {
                name  = "RENOVATE_AUTODISCOVER"
                value = "false"
              }
              env {
                name  = "RENOVATE_REPOSITORIES"
                value = jsonencode(["CampFireMan/go-tube", "CampFireMan/home-lab"])
              }
              # Trusts the cluster's internal CA (mounted below) so the
              # docker datasource can verify registry.home.arpa's cert
              # instead of just failing the TLS handshake. A hostRules
              # insecureRegistry override was tried first but only made
              # Renovate attempt plain HTTP, which the ingress 301-redirects
              # back to HTTPS anyway — same verification failure either way.
              env {
                name  = "NODE_EXTRA_CA_CERTS"
                value = "/etc/ssl/renovate/internal-ca.pem"
              }

              volume_mount {
                name       = "internal-ca"
                mount_path = "/etc/ssl/renovate"
                read_only  = true
              }

              # Single-node cluster shared with every other home-lab
              # service — keep resource asks modest, same reasoning as
              # gitlab_runner.tf.
              resources {
                requests = {
                  cpu    = "100m"
                  memory = "256Mi"
                }
                limits = {
                  cpu    = "500m"
                  memory = "2048Mi"
                }
              }
            }

            volume {
              name = "internal-ca"
              config_map {
                name = kubernetes_config_map_v1.renovate_internal_ca.metadata.0.name
              }
            }
          }
        }
      }
    }
  }
}
