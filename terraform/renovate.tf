locals {
  renovate_name    = "renovate"
  renovate_version = "43.281.0"
}

resource "kubernetes_namespace" "renovate_namespace" {
  metadata {
    name = local.renovate_name
  }
}

resource "kubernetes_secret" "renovate_secrets" {
  metadata {
    name      = "${local.renovate_name}-secrets"
    namespace = kubernetes_namespace.renovate_namespace.metadata.0.name
  }
  data = {
    RENOVATE_TOKEN = data.sops_file.secrets.data["renovate_gitlab_token"]
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
    namespace = kubernetes_namespace.renovate_namespace.metadata.0.name
  }

  spec {
    schedule                      = "0 */4 * * *"
    concurrency_policy            = "Forbid"
    successful_jobs_history_limit = 3
    failed_jobs_history_limit     = 3

    job_template {
      metadata {
        name      = local.renovate_name
        namespace = kubernetes_namespace.renovate_namespace.metadata.0.name
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
                  name     = kubernetes_secret.renovate_secrets.metadata.0.name
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
              # registry.home.arpa uses a self-signed cert with no CA
              # trusted by this image's Node.js runtime — same reason
              # go-tube's own CI passes dind `--insecure-registry` for it
              # (see .gitlab-ci.yml). Without this, every docker datasource
              # lookup against it fails with UNABLE_TO_VERIFY_LEAF_SIGNATURE.
              env {
                name = "RENOVATE_HOST_RULES"
                value = jsonencode([
                  {
                    matchHost        = "registry.home.arpa"
                    hostType         = "docker"
                    insecureRegistry = true
                  }
                ])
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
                  memory = "512Mi"
                }
              }
            }
          }
        }
      }
    }
  }
}
