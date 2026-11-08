#!/bin/bash
# Запуск тесту однією командою (з кореня проєкту):  ./loadtest/run.sh
#
# Інші варіанти:
#   VUS=60 ./loadtest/run.sh                (інше N)
#   QUICK=1 VUS=2 ./loadtest/run.sh         (короткий пробний запуск)
#   BASE_URL=http://localhost:5000 ADMIN_PASSWORD=localadmin ./loadtest/run.sh   (локально)

cd "$(dirname "$0")/.."

# Адреса й пароль беремо з Terraform, у репозиторії їх немає
BASE_URL=${BASE_URL:-$(terraform -chdir=deploy/azure/terraform output -raw service_url)}
ADMIN_PASSWORD=${ADMIN_PASSWORD:-$(terraform -chdir=deploy/azure/terraform output -raw admin_password)}

mkdir -p loadtest/results
FILE=loadtest/results/run-$(date +%Y%m%d-%H%M%S).txt

echo "Початок: $(date +%H:%M:%S)"
k6 run \
  -e BASE_URL="$BASE_URL" \
  -e ADMIN_PASSWORD="$ADMIN_PASSWORD" \
  -e VUS="${VUS:-40}" \
  -e QUICK="${QUICK:-0}" \
  loadtest/loadtest.js | tee "$FILE"
echo "Кінець: $(date +%H:%M:%S). Результат збережено в $FILE"
