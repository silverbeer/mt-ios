#!/usr/bin/env bash
# Copy TestFlight signing secrets from 1Password into this repo's GitHub Actions secrets.
# Values are piped straight through; nothing is printed.
#
# 1Password item (vault "agents" by default):
#   mt-ios-asc   fields: key_id, issuer_id, team_id, private_key (contents of AuthKey_XXXX.p8)
set -euo pipefail
vault="${OP_VAULT:-agents}"
item="${OP_ITEM:-mt-ios-asc}"
repo="${GH_REPO:-silverbeer/mt-ios}"

put() {
  local secret="$1" field="$2"
  op read "op://$vault/$item/$field" | gh secret set "$secret" --repo "$repo"
  echo "set $secret"
}

put ASC_KEY_ID key_id
put ASC_ISSUER_ID issuer_id
put APPLE_TEAM_ID team_id
put ASC_KEY_P8 private_key
