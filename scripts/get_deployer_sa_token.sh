#!/bin/bash

# Prints the current token. Consumed via `sops` (terraform/secrets.enc.json,
# key "deployer_service_account_token") to rotate the stored value -- not
# via /tmp/token anymore.
ssh -q -t ture@elmaestro "sudo kubectl get secret deployer-service-account-token -o jsonpath='{.data.token}' | base64 -d"
