SHELL := /bin/bash

BACKUP_NAME=full-cluster-backup-manual-$(shell date +'%Y-%m-%d--%H-%M-%S')
VAULT_PASSWORD_PATH=~/.ansible-vault-password
ANSIBLE_DIR=./ansible
INVENTORY_PATH=$(ANSIBLE_DIR)/inventory/home-lab/hosts.ini

define playbook
	ansible-playbook "$(ANSIBLE_DIR)/$(1)" --vault-password-file=${VAULT_PASSWORD_PATH} -i ${INVENTORY_PATH} -K $(2)
endef

define playbook_with_tag
	$(call playbook,site.yml, -t $(1))
endef

create-ca:
	openssl req -x509 -newkey ec:<(openssl ecparam -name secp384r1) -sha256 -days 3650 -nodes -keyout cluster_t.key -out cluster_t.cer
	cat cluster.key | base64 | tr -d '\n' > cluster.key.base64
	cat cluster.cer | base64 | tr -d '\n' > cluster.cer.base64

install-requirements:
	ansible-galaxy install -r "$(ANSIBLE_DIR)/requirements.yml"

reset: install-requirements
	$(call playbook,reset.yml)

deploy: install-requirements
	$(call playbook,site.yml)

deploy-services: install-requirements
	$(call playbook_with_tag,services)

deploy-master-infra: install-requirements
	$(call playbook_with_tag,master-infra)

deploy-zimaboard: install-requirements
	$(call playbook_with_tag,zimaboard)

deploy-picam: install-requirements
	$(call playbook_with_tag,picam)

deploy-tailscale: install-requirements
	$(call playbook_with_tag,tailscale)

deploy-common-infra: install-requirements
	$(call playbook_with_tag,common-infra)

terraform-init:
	./scripts/terraform.sh init terraform

terraform-plan: terraform-init
	./scripts/terraform.sh plan terraform deployer_service_account_token="$$(cat /tmp/token)"

terraform-apply: terraform-init
	./scripts/terraform.sh apply terraform deployer_service_account_token="$$(cat /tmp/token)"

cluster-backup:
	ssh -t ture@192.168.1.67 "sudo velero backup create ${BACKUP_NAME} --kubeconfig=/home/home-lab/.kube/config --wait && \
	sudo velero backup describe ${BACKUP_NAME} --kubeconfig=/home/home-lab/.kube/config"
