BACKUP_NAME=full-cluster-backup-manual-$(shell date +'%Y-%m-%d--%H-%M-%S')

create-ca:
	openssl req -x509 -newkey ec:<(openssl ecparam -name secp384r1) -sha256 -days 3650 -nodes -keyout cluster_t.key -out cluster_t.cer
	cat cluster.key | base64 | tr -d '\n' > cluster.key.base64
	cat cluster.cer | base64 | tr -d '\n' > cluster.cer.base64

install-requirements:
	ansible-galaxy install -r requirements.yml

reset: install-requirements
	ansible-playbook reset.yml  --vault-password-file=~/.ansible-vault-password -i inventory/home-lab/hosts.ini -K

deploy: install-requirements
	ansible-playbook site.yml  --vault-password-file=~/.ansible-vault-password -i inventory/home-lab/hosts.ini -K

deploy-services: install-requirements
	ansible-playbook site.yml  --vault-password-file=~/.ansible-vault-password -i inventory/home-lab/hosts.ini -K -t services

deploy-master-infra: install-requirements
	ansible-playbook site.yml  --vault-password-file=~/.ansible-vault-password -i inventory/home-lab/hosts.ini -K -t master-infra

cluster-backup:
	ssh -t ture@192.168.1.67 "sudo velero backup create ${BACKUP_NAME} --kubeconfig=/home/home-lab/.kube/config --wait && \
	sudo velero backup describe ${BACKUP_NAME} --kubeconfig=/home/home-lab/.kube/config"
