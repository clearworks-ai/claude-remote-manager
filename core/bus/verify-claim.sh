#!/usr/bin/env bash
# verify-claim.sh — Log a verified fact to the verification ledger
# Used by Frank before sending Telegram messages with factual claims.
#
# Usage:
#   verify-claim.sh "Matt Owens meeting Tue Apr 7 at 2pm"
#   verify-claim.sh "Tax extension due Apr 15" "checked IRS website"
#   verify-claim.sh --clear   # Clear all entries (fresh start)
#   verify-claim.sh --show    # Show current ledger
#
# The verification gate hook (verification-gate.js) reads this ledger
# and blocks messages containing factual claims not found here.
# Entries expire after 10 minutes automatically.

set -euo pipefail

LEDGER_PATH="/tmp/frank-verification-ledger.jsonl"

case "${1:-}" in
    --clear)
        > "$LEDGER_PATH"
        echo "Ledger cleared"
        exit 0
        ;;
    --show)
        if [[ -f "$LEDGER_PATH" ]]; then
            cat "$LEDGER_PATH"
        else
            echo "No ledger found"
        fi
        exit 0
        ;;
    "")
        echo "Usage: verify-claim.sh <claim> [source]"
        echo "       verify-claim.sh --clear"
        echo "       verify-claim.sh --show"
        exit 1
        ;;
esac

CLAIM="$1"
SOURCE="${2:-tool-verified}"
TIMESTAMP=$(date +%s000)  # milliseconds

# Append to ledger
echo "{\"claim\":\"${CLAIM}\",\"source\":\"${SOURCE}\",\"timestamp\":${TIMESTAMP}}" >> "$LEDGER_PATH"

echo "VERIFIED: ${CLAIM} (${SOURCE})"
