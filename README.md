## Лабораторна роботи з дисципліни " Хмарні технології"
## Виконала: Цапів Анастасія(IP-31)
## Лабораторна робота №1 
# Cars API: розгортання в Azure (Terraform)

REST API каталогу автомобілів (Flask + Flask-RESTful + SQLAlchemy, PostgreSQL).
Запакований у Docker, інфраструктура описана в Terraform, розгорнуто в Azure
за Application Gateway, автодеплой через GitHub Actions (OIDC).

**Публічна адреса:** `http://<IP gateway>` (після `apply` береться з `terraform output service_url`)
Swagger UI: `<адреса>/apidocs/`

## Ендпоінти

| Метод | Шлях | Доступ |
|---|---|---|
| GET | `/api/cars/`, `/api/cars/<id>`, `/api/cars/total_price/` | відкритий |
| POST | `/api/cars/` | JWT |
| PATCH, DELETE | `/api/cars/<id>` | JWT |
| POST | `/api/login` | видає токен |
| GET | `/health`, `/version` | відкритий |

## Структура репозиторію
Уся інфраструктура — в `terraform/`. Один `terraform apply` створює:

| Файл | Що створює |
|---|---|
| `api.py`, `requirements.txt` | код застосунку |
| `Dockerfile` | образ: фіксована база, залежності окремим шаром, користувач не root |
| `compose.yaml` | застосунок + PostgreSQL локально, дані в volume `pgdata` |
| `.github/workflows/deploy.yml` | push у main → збірка → push в ACR з тегом = sha коміту → оновлення Container App |
| `deploy/azure/terraform/group_azure.tf` | resource group |
| `.../acr.tf` | реєстр образів + збірка початкового образу |
| `.../network.tf` | VNet, підмережі, private DNS, NSG бази |
| `.../database.tf` | PostgreSQL Flexible Server, секрети JWT, моніторинг |
| `.../containerapp.tf` | середовище та Container App |
| `.../appgw.tf` | Application Gateway з health probe `/health` |
| `.../cicd.tf` | managed identity, federated credential (OIDC), ролі |
| `.../budget.tf` | бюджет із сповіщенням на email |
| `.../outputs.tf`, `variables.tf`, `providers.tf` | виводи, змінні, провайдери |

## Локальний запуск
```bash
docker compose up --build -d
curl localhost:5000/health
docker compose down     
```

## Розгортання в Azure
```bash
cd deploy/azure/terraform
# terraform.tfvars (у .gitignore): budget_email, github_repo
az login
terraform init
terraform apply
terraform output service_url
```

## CI/CD
1. `terraform output client_id` → GitHub Variables: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`.
2. Push у `main` запускає workflow, вхід в Azure через OIDC без ключів.
3. Образ тегується хешем коміту. Відкат: `az containerapp update --image <registry>/cars-api:<старий sha>`.

## Мережа та безпека
- База в приватній підмережі, `publicNetworkAccess = Disabled`.
- NSG бази дозволяє порт 5432 лише з підмережі застосунку.
- Середовище Container Apps внутрішнє, з інтернету видно лише Application Gateway.
- Паролі (БД, JWT, admin) генерує Terraform і передає через secrets контейнера.

## Моніторинг
Логи в Log Analytics, дашборд із метриками, алерт на 5xx з email.

## Прибрати все
``terraform destroy```

## Свідомі спрощення
- NSG: джерело правила це підмережа застосунку, бо Container Apps не можна додати в Application Security Group.
- Тільки HTTP без сертифіката.
- ACR з `admin_enabled` для pull образу (CI працює через OIDC).
- State локальний.