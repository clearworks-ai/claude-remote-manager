#!/usr/bin/env bash
#
# cp.sh — programmatic Clearpath API caller for the clearpath-dev agent.
#
# Usage:
#   bash scripts/cp.sh <path> [curl-args...]
#
# Examples:
#   bash scripts/cp.sh /api/agreement-templates
#   bash scripts/cp.sh /api/agreement-templates/5
#   bash scripts/cp.sh /api/briefings/generate -X POST -d '{...}' \
#       -H 'content-type: application/json'
#
# Reads the API key from ~/.clearworks/clearpath-api-key. Create one with:
#   cd ~/code/clearpath && \
#     npx tsx server/scripts/create-agent-api-key.ts <orgId> <userId> "clearpath-dev agent"
#
# Always hits https://clrpath.ai (canonical domain — the Railway URL
# 301-redirects and drops x-api-key).

set -euo pipefail

KEY_FILE="${CLEARPATH_API_KEY_FILE:-$HOME/.clearworks/clearpath-api-key}"
BASE_URL="${CLEARPATH_BASE_URL:-https://clrpath.ai}"

if [[ ! -f "$KEY_FILE" ]]; then
  echo "error: API key not found at $KEY_FILE" >&2
  echo "generate one with:" >&2
  echo "  cd ~/code/clearpath && npx tsx server/scripts/create-agent-api-key.ts <orgId> <userId> 'clearpath-dev agent'" >&2
  exit 1
fi

API_KEY="$(cat "$KEY_FILE")"

if [[ $# -lt 1 ]]; then
  echo "usage: cp.sh <path> [curl-args...]" >&2
  exit 1
fi

path="$1"
shift

curl -sSL \
  -H "x-api-key: $API_KEY" \
  -H "accept: application/json" \
  "$@" \
  "${BASE_URL}${path}"
