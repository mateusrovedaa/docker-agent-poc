#!/bin/bash
set -a
source "$(dirname "$0")/.env"
set +a

# Mapeia LLM_API_KEY para a variável do provider correto
PROVIDER=$(echo "$LLM_MODEL" | cut -d'/' -f1)
case "$PROVIDER" in
  google)    export GOOGLE_API_KEY="$LLM_API_KEY" ;;
  anthropic) export ANTHROPIC_API_KEY="$LLM_API_KEY" ;;
  openai)    export OPENAI_API_KEY="$LLM_API_KEY" ;;
esac

exec docker agent run "$(dirname "$0")/pipeline.yaml" "$@"
