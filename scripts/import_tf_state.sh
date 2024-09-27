#!/bin/bash

# Set the namespace
NAMESPACE=${1}
SCRIPT_DIR=$(dirname "${0}")
PROJECT_DIR=$(dirname "${SCRIPT_DIR}")
TF_IMPORT_CMD="${SCRIPT_DIR}/terraform.sh import ${PROJECT_DIR}/terraform deployer_service_account_token=$(cat /tmp/token)"

if [ -z "${NAMESPACE}" ]; then
    echo "Usage: ${0} <namespace>"
    exit 1
fi

# Function to import a resource
import_resource() {
    RESOURCE_TYPE=$1
    RESOURCE_NAME=$2
    TF_RESOURCE_NAME=$3

    echo "Importing $RESOURCE_TYPE/$RESOURCE_NAME as $TF_RESOURCE_NAME"
    ${TF_IMPORT_CMD} "kubernetes_$TF_RESOURCE_NAME.$RESOURCE_NAME" "$NAMESPACE/$RESOURCE_NAME"
}

# Import namespace
${TF_IMPORT_CMD} "kubernetes_namespace.${NAMESPACE}" $NAMESPACE

# Import ConfigMap
for cm in $(kubectl get configmap -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}'); do
    import_resource "configmap" $cm "config_map"
done

# Import Secrets
for secret in $(kubectl get secret -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}'); do
    import_resource "secret" $secret "secret"
done

# Import ServiceAccounts
for sa in $(kubectl get serviceaccount -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}'); do
    import_resource "serviceaccount" $sa "service_account"
done

# Import PersistentVolumeClaims
for pvc in $(kubectl get pvc -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}'); do
    import_resource "pvc" $pvc "persistent_volume_claim"
done

# Import Deployments
for deploy in $(kubectl get deployment -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}'); do
    import_resource "deployment" $deploy "deployment"
done

# Import Services
for svc in $(kubectl get service -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}'); do
    import_resource "service" $svc "service"
done

# Import Ingresses
for ing in $(kubectl get ingress -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}'); do
    import_resource "ingress" $ing "ingress_v1"
done

echo "Import complete. Please check your Terraform state."