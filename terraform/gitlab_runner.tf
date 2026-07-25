locals {
  gitlab_runner_name = "gitlab-runner"
}

resource "kubernetes_namespace" "gitlab_runner_namespace" {
  metadata {
    name = local.gitlab_runner_name
  }
}

# Requires "gitlab_runner_token" (a glrt-... runner authentication token,
# created via GitLab > Settings > CI/CD > Runners > New runner) to exist in
# secrets.enc.json before this can be applied.
resource "helm_release" "gitlab_runner" {
  name       = local.gitlab_runner_name
  namespace  = kubernetes_namespace.gitlab_runner_namespace.metadata.0.name
  repository = "https://charts.gitlab.io"
  chart      = "gitlab-runner"
  version    = "0.80.1"

  values = [
    yamlencode({
      gitlabUrl = "https://gitlab.com/"

      # Single-node cluster shared with every other home-lab service — keep
      # concurrency and resource asks modest so a build can't starve
      # jellyfin/postgres/grafana etc.
      concurrent    = 1
      checkInterval = 30

      rbac = {
        create = true
      }

      resources = {
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
        limits = {
          cpu    = "500m"
          memory = "512Mi"
        }
      }

      runners = {
        # Not picked up by every job in every project by default — only
        # jobs that explicitly set `tags: [home-lab]` land here (see
        # go-tube's build-image/canary-gate/publish-latest jobs).
        tags        = "home-lab"
        runUntagged = false

        # Kubernetes executor, privileged pod so the per-job docker:27-dind
        # service can build images. Trusting registry.home.arpa's
        # self-signed cert is configured per-job in .gitlab-ci.yml (dind
        # service `command:`), not here, so it stays visible next to the
        # jobs that actually need it.
        config = <<-TOML
          [[runners]]
            [runners.kubernetes]
              namespace = "${local.gitlab_runner_name}"
              image = "docker:27"
              privileged = true
              poll_timeout = 600
              cpu_request = "250m"
              memory_request = "256Mi"
              cpu_limit = "1"
              memory_limit = "1Gi"
              service_cpu_request = "500m"
              service_memory_request = "512Mi"
              service_cpu_limit = "2"
              service_memory_limit = "2Gi"
        TOML
      }
    })
  ]

  set_sensitive {
    name  = "runnerToken"
    value = data.sops_file.secrets.data["gitlab_runner_token"]
  }
}
