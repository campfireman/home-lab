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
        # Tags and "run untagged" are NOT set here: with the runner
        # authentication token flow (glrt-...), those are server-side
        # properties of the runner record in GitLab itself (Settings >
        # CI/CD > Runners > this runner > Edit) — the old config.toml/Helm
        # `tags`/`runUntagged` values are ignored for this flow. Set the
        # "home-lab" tag there to match go-tube's
        # build-image/canary-gate/publish-latest jobs.

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
            # Without this, the executor considers the pod "ready" as soon as
            # its containers reach Running phase, not once dind has actually
            # finished starting dockerd — a race that broke docker buildx
            # create's connection to the dind service.
            [runners.feature_flags]
              FF_WAIT_FOR_POD_TO_BE_REACHABLE = true
        TOML
      }
    })
  ]

  set_sensitive {
    name  = "runnerToken"
    value = data.sops_file.secrets.data["gitlab_runner_token"]
  }
}
