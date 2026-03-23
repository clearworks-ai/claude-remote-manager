#!/usr/bin/env bash
# send-ask-question.sh - Send the Nth question from the ask state file to Telegram
# Called by fast-checker when advancing to the next question in multi-question flows.
# Usage: send-ask-question.sh <question_index>

set -uo pipefail

Q_IDX="${1:?Usage: send-ask-question.sh <question_index>}"

TEMPLATE_ROOT="${CRM_TEMPLATE_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
AGENT="${CRM_AGENT_NAME:-$(basename "$(pwd)")}"

ENV_FILE="${TEMPLATE_ROOT}/agents/${AGENT}/.env"
{ set +x; } 2>/dev/null
if [[ -f "$ENV_FILE" ]]; then
    set -a; source "$ENV_FILE"; set +a
elif [[ -f ".env" ]]; then
    set -a; source ".env"; set +a
fi

if [[ -z "${BOT_TOKEN:-}" ]] || [[ -z "${CHAT_ID:-}" ]]; then
    exit 1
fi

STATE_FILE="/tmp/crm-ask-state-${AGENT}.json"
if [[ ! -f "$STATE_FILE" ]]; then
    exit 1
fi

source "${TEMPLATE_ROOT}/core/bus/_telegram-curl.sh"

TOTAL_Q=$(jq -r '.total_questions // 1' "$STATE_FILE" 2>/dev/null)
Q_TEXT=$(jq -r ".questions[${Q_IDX}].question // \"Question\"" "$STATE_FILE" 2>/dev/null)
Q_HEADER=$(jq -r ".questions[${Q_IDX}].header // empty" "$STATE_FILE" 2>/dev/null || echo "")
Q_MULTI=$(jq -r ".questions[${Q_IDX}].multiSelect // false" "$STATE_FILE" 2>/dev/null)
Q_OPTIONS=$(jq -c ".questions[${Q_IDX}].options // []" "$STATE_FILE" 2>/dev/null)
Q_OPT_COUNT=$(echo "$Q_OPTIONS" | jq 'length' 2>/dev/null || echo "0")

MSG="QUESTION ($((Q_IDX+1))/${TOTAL_Q}) - ${AGENT}:"
[[ -n "$Q_HEADER" ]] && MSG+="
${Q_HEADER}"
MSG+="
${Q_TEXT}
"

if [[ "$Q_MULTI" == "true" ]]; then
    MSG+="
(Multi-select: tap options to toggle, then tap Submit)"
fi

for i in $(seq 0 $((Q_OPT_COUNT - 1))); do
    LABEL=$(echo "$Q_OPTIONS" | jq -r ".[$i] // \"Option $((i+1))\"" 2>/dev/null)
    MSG+="
$((i+1)). ${LABEL}"
done

if [[ "$Q_MULTI" == "true" ]]; then
    KEYBOARD=$(echo "$Q_OPTIONS" | jq -c '[to_entries[] | [{
        text: (.value // "Option \(.key + 1)"),
        callback_data: "asktoggle_'"$Q_IDX"'_\(.key)"
    }]] + [[{text: "Submit Selections", callback_data: "asksubmit_'"$Q_IDX"'"}]]' 2>/dev/null)
else
    KEYBOARD=$(echo "$Q_OPTIONS" | jq -c '[to_entries[] | [{
        text: (.value // "Option \(.key + 1)"),
        callback_data: "askopt_'"$Q_IDX"'_\(.key)"
    }]]' 2>/dev/null)
fi
KEYBOARD="{\"inline_keyboard\":${KEYBOARD}}"

telegram_api_post "sendMessage" \
    -H "Content-Type: application/json" \
    -d "$(jq -n -c \
        --arg chat_id "$CHAT_ID" \
        --arg text "$MSG" \
        --argjson reply_markup "$KEYBOARD" \
        '{chat_id: $chat_id, text: $text, reply_markup: $reply_markup}')" > /dev/null 2>&1
