BACKUP_NAME=full-cluster-backup-manual-$(shell date +'%Y-%m-%d--%H-%M-%S')
VAULT_PASSWORD_PATH=~/.ansible-vault-password
INVENTORY_PATH=./inventory/home-lab/hosts.ini

define playbook
	ansible-playbook $(1) --vault-password-file=${VAULT_PASSWORD_PATH} -i ${INVENTORY_PATH} -K $(2)
endef

define playbook_with_tag
	$(call playbook, site.yml, -t $(1))
endef

create-ca:
	openssl req -x509 -newkey ec:<(openssl ecparam -name secp384r1) -sha256 -days 3650 -nodes -keyout cluster_t.key -out cluster_t.cer
	cat cluster.key | base64 | tr -d '\n' > cluster.key.base64
	cat cluster.cer | base64 | tr -d '\n' > cluster.cer.base64

install-requirements:
	ansible-galaxy install -r requirements.yml

reset: install-requirements
	$(call playbook, reset.yml)

deploy: install-requirements
	$(call playbook, site.yml)

deploy-services: install-requirements
	$(call playbook_with_tag, services)

deploy-master-infra: install-requirements
	$(call playbook_with_tag, master-infra)

cluster-backup:
	ssh -t ture@192.168.1.67 "sudo velero backup create ${BACKUP_NAME} --kubeconfig=/home/home-lab/.kube/config --wait && \
	sudo velero backup describe ${BACKUP_NAME} --kubeconfig=/home/home-lab/.kube/config"
