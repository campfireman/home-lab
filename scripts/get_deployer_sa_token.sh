#!/bin/bash

ssh -q -t ture@elmaestro "sudo kubectl get secret deployer-service-account-token -o jsonpath='{.data.token}' | base64 -d"
