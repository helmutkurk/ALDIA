#!/usr/bin/env bash
# Checks the embedding API keys with one short text request per provider.
# Reads AWS_BEARER_TOKEN_BEDROCK and GEMINI_API_KEY from the environment and
# asks for missing keys without echoing them, and prints only the HTTP status and the start of the answer, never a key.
# Keys are passed to curl through a process substitution, so they do not
# appear in the process list. Usage: bash training/check_keys.sh
set -u

REGION="${EMBEDDING_REGION:-us-east-1}"

# Ask for missing keys without echoing them (Enter skips a provider).
if [ -z "${AWS_BEARER_TOKEN_BEDROCK:-}" ] && [ -t 0 ]; then
  read -rsp "Bedrock-Key (Enter = ueberspringen): " AWS_BEARER_TOKEN_BEDROCK; echo
fi
if [ -z "${GEMINI_API_KEY:-}" ] && [ -t 0 ]; then
  read -rsp "Gemini-Key (Enter = ueberspringen): " GEMINI_API_KEY; echo
fi
TEXT="un bache en la calle"

show() {
  local name="$1" status="$2" body="$3"
  echo "== $name: HTTP $status"
  # Shorten long number lists so the shape stays readable.
  printf '%s\n' "${body:0:400}" | sed -E 's/(-?[0-9]+\.[0-9]+,){3,}/<zahlen>,/g'
  echo
}

if [ -n "${AWS_BEARER_TOKEN_BEDROCK:-}" ]; then
  out="$(curl -sS --max-time 30 -w '\n%{http_code}' \
    "https://bedrock-runtime.${REGION}.amazonaws.com/model/amazon.nova-2-multimodal-embeddings-v1%3A0/invoke" \
    -H @<(printf 'Authorization: Bearer %s\n' "$AWS_BEARER_TOKEN_BEDROCK") \
    -H 'Content-Type: application/json' \
    -d "{\"schemaVersion\":\"nova-multimodal-embed-v1\",\"taskType\":\"SINGLE_EMBEDDING\",\"singleEmbeddingParams\":{\"embeddingPurpose\":\"IMAGE_RETRIEVAL\",\"embeddingDimension\":256,\"text\":{\"truncationMode\":\"END\",\"value\":\"$TEXT\"}}}")"
  show "Amazon ($REGION)" "${out##*$'\n'}" "${out%$'\n'*}"
else
  echo "== Amazon: AWS_BEARER_TOKEN_BEDROCK ist leer, uebersprungen"
  echo
fi

if [ -n "${GEMINI_API_KEY:-}" ]; then
  out="$(curl -sS --max-time 30 -w '\n%{http_code}' \
    "https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-2:embedContent" \
    -H @<(printf 'x-goog-api-key: %s\n' "$GEMINI_API_KEY") \
    -H 'Content-Type: application/json' \
    -d "{\"content\":{\"parts\":[{\"text\":\"$TEXT\"}]},\"output_dimensionality\":256}")"
  show "Google" "${out##*$'\n'}" "${out%$'\n'*}"
else
  echo "== Google: GEMINI_API_KEY ist leer, uebersprungen"
fi
