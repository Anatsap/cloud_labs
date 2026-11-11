#!/bin/bash

cd "$(dirname "$0")/.."
BASE_URL=${BASE_URL:-$(terraform -chdir=deploy/azure/terraform output -raw service_url)}
ADMIN_PASSWORD=${ADMIN_PASSWORD:-$(terraform -chdir=deploy/azure/terraform output -raw admin_password)}

mkdir -p loadtest/results
FILE=loadtest/results/run-$(date +%Y%m%d-%H%M%S).txt

echo "Початок: $(date +%H:%M:%S)"
k6 run \
  -e BASE_URL="$BASE_URL" \
  -e ADMIN_PASSWORD="$ADMIN_PASSWORD" \
  -e VUS="${VUS:-100}" \
  -e QUICK="${QUICK:-0}" \
  loadtest/loadtest.js | tee "$FILE"
echo "Кінець: $(date +%H:%M:%S). Результат збережено в $FILE"
