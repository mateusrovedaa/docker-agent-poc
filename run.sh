#!/bin/bash
set -a
source "$(dirname "$0")/.env"
set +a

PROVIDER=$(echo "$LLM_MODEL" | cut -d'/' -f1)
case "$PROVIDER" in
  google)    export GOOGLE_API_KEY="$LLM_API_KEY" ;;
  anthropic) export ANTHROPIC_API_KEY="$LLM_API_KEY" ;;
  openai)    export OPENAI_API_KEY="$LLM_API_KEY" ;;
esac

TMPFILE=$(mktemp /tmp/pipeline-XXXXXX.yaml)
trap "rm -f $TMPFILE" EXIT
envsubst < "$(dirname "$0")/pipeline.yaml" > "$TMPFILE"

exec docker agent run "$TMPFILE" "$@"
