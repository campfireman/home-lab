#!/bin/bash
# Source this script, do not run it: `source ./scripts/load_n8n_mcp_env.sh`
# Running it as a subprocess cannot export the token into your shell.

set -euo pipefail

PROJECT_DIR=$(git rev-parse --show-toplevel)
SECRETS_FILE="${PROJECT_DIR}/terraform/secrets.enc.json"

export N8N_MCP_TOKEN=$(sops -d --extract '["n8n_mcp_token"]' "${SECRETS_FILE}")
echo "N8N_MCP_TOKEN exported for this shell."
