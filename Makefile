create-ca:
	openssl req -x509 -newkey ec:<(openssl ecparam -name secp384r1) -sha256 -days 3650 -nodes -keyout cluster_t.key -out cluster_t.cer
	cat cluster.key | base64 | tr -d '\n' > cluster.key.base64
	cat cluster.cer | base64 | tr -d '\n' > cluster.cer.base64