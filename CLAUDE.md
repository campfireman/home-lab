# CLAUDE.md

## About this repository

This repository holds the config for campfireman's home lab. The lab has two nodes:

- **zimaboard** (192.168.1.67): runs Docker services. Ansible manages this node.
- **elmaestro** (192.168.1.102): runs a k3s cluster. Terraform manages most services on this node. Ansible sets up the node and the cluster itself.

## Guiding principles

1. **Keep it simple.** Use simple tools. Avoid complex abstractions.
2. **Support learning.** The owner must understand every part of the system. Do not add a tool or pattern that hides how it works.
3. **Do not use Helm charts.** Use typed Terraform Kubernetes resources instead, for example `kubernetes_deployment_v1` or `kubernetes_service_v1`. The `gitlab-runner` Helm release is the one exception. Do not add new Helm releases.
4. **Prefer explicit code over generic code.** Use typed Terraform resources. Do not use generic `kubernetes_manifest` blocks.

Follow these principles when you propose a change. If a task needs a complex tool or a new abstraction, say so and explain the trade-off. Let the owner decide.

## Directory structure

- `ansible/`: playbooks and roles for host setup and Docker services.
  - `site.yml`: the main playbook. It runs roles by tag.
  - `roles/k3s/*`: installs the k3s cluster.
  - `roles/master-infra`: sets up Longhorn and the deployer service account on elmaestro.
  - `roles/zimaboard`: sets up Home Assistant, pi-hole, NFS, and rclone on zimaboard.
  - `roles/common-infra`: sets up node-exporter and smartctl-exporter on all hosts.
- `terraform/`: config for services on the k3s cluster. One file per service, in the `terraform/` root.
  - `modules/ingress/`: the one shared module. It creates a Kubernetes ingress and a pi-hole DNS record.
  - `secrets.enc.json`: secrets, encrypted with sops.
- `scripts/`: helper scripts for Terraform and secret rotation.
- `docs/`: a hardware photo. No architecture docs exist yet. Use this file as the main reference.

## Secrets

Secrets use `sops`. Never put a plain secret value in a commit, in chat output, or in a tool result.

## CI/CD

GitLab CI runs one job: `terraform-apply`. It runs on a self-hosted runner inside the cluster. It triggers on push to `master` when Terraform files change, and once a day to fix drift. There is no CI for Ansible yet.

## Known issues and active work

- **The Ansible-to-Terraform migration is not finished.** Some services still run through Ansible and Docker on zimaboard. Move a service to Terraform only when it makes the setup simpler, not to move it for its own sake.
- **Terraform has circular dependencies.** Two examples exist today:
  1. The Terraform Kubernetes and Helm providers need an auth token. Only Ansible can create this token, on the cluster. A human must copy the token into the secrets file by hand.
  2. `grafana.tf` creates the Grafana deployment and also uses the `grafana` provider to configure it. Terraform cannot order these two steps on its own.

  The fix in progress: split Terraform into layers, for example a bootstrap layer, a cluster-services layer, and an app layer. Each layer must pass its output to the next layer through Terraform state, not through a manual copy step. Suggest this pattern when it fits a task.

## Planned projects

Keep these in mind. Prefer solutions that fit the guiding principles above.

- Add a logging sink for the cluster.
- Set up a new node with OPNsense. It will replace the current ASUS router.
- Add long-term storage for Home Assistant data.
- Add more workloads that give value at home.
- Review security, with a focus on agentic AI attackers.

## Working conventions

- Read `README.md` and this file before you make a change.
- Prefer small, reviewable changes. Do not make a large refactor without the owner's agreement.
- Add a new Terraform resource to the file that already covers that service. Create a new file only for a new service.
- Explain trade-offs before you use a new tool or pattern.
- Write commit messages in the past tense. Start with a verb, for example "Added ...", "Fixed ...", "Refactored ...".
- For any documentation or writing stick to ASD-STE100 Simplified Technical English.
