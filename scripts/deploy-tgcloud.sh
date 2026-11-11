#!/usr/bin/env bash
# S16 / R16 — tgcloud Serverless deployment.
# Tokens come ONLY from env: TGCLI_TOKEN (login) and BOT_TOKEN (runtime env).
# Never hardcode tokens here.
set -euo pipefail

: "${TGCLI_TOKEN:?TGCLI_TOKEN must be set in the environment}"
: "${BOT_TOKEN:?BOT_TOKEN must be set in the environment}"

PROJECT_NAME="${1:-Wavely_MusicBot}"

echo "==> tgcloud login (CLI token from env)"
npx --yes @tgcloud/bot login <<< "$TGCLI_TOKEN"

echo "==> build"
npm run build

echo "==> push"
npx --yes @tgcloud/bot push

echo "==> migrate"
npx --yes @tgcloud/bot migrate

echo "==> deployment of $PROJECT_NAME complete"
