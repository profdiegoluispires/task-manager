terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
  }
}

# PostgreSQL Flexible Server e App Service exigem nomes únicos em todo o Azure
# (não só na assinatura) — "task-manager-db"/"task-manager-app" já colidiram
# com servidores de outras contas. Sufixo estável evita esse conflito.
resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

provider "azurerm" {
  features {}
  # Registra automaticamente os resource providers usados pela config (ex.:
  # Microsoft.ContainerRegistry, Microsoft.Web, Microsoft.DBforPostgreSQL) —
  # necessário em assinaturas novas (como Azure for Students) que ainda não
  # têm esses namespaces habilitados.
  resource_provider_registrations = "extended"
}

# Nome próprio (diferente do rg-task-manager usado em az-activity-vm) — os dois
# diretórios são stacks independentes, cada um com seu próprio state; usar o
# mesmo nome de resource group causaria conflito de criação entre eles.
resource "azurerm_resource_group" "rg" {
  name = "rg-task-manager-container"
  # eastus2 é a mais barata em geral, mas esta assinatura está bloqueada para
  # provisionar PostgreSQL Flexible Server ali ("Subscriptions are restricted
  # from provisioning in this region"). northcentralus é a mais barata entre as
  # regiões liberadas que realmente suportam o Postgres Flexible Server aqui.
  location = "northcentralus"
}

resource "azurerm_container_registry" "acr" {
  name                = "meuacrtaskmanager"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = true
}

resource "azurerm_service_plan" "plan" {
  name                = "plano-task-manager"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  os_type             = "Linux"
  # F1 (Free) não suporta containers Linux customizados no App Service.
  sku_name = "B1"
}

# Banco gerenciado equivalente ao serviço "postgres" do docker-compose.yml.
# O App Service (Web App for Containers) roda um único container por app, então,
# diferente do sidecar usado no Cloud Run, aqui o postgres:15 vira um Flexible
# Server gerenciado pelo Azure.
resource "azurerm_postgresql_flexible_server" "db" {
  name                   = "task-manager-db-${random_string.suffix.result}"
  resource_group_name    = azurerm_resource_group.rg.name
  location               = azurerm_resource_group.rg.location
  version                = "15"
  administrator_login    = "taskmanager"
  administrator_password = "TaskManager123!"
  storage_mb             = 32768
  sku_name               = "B_Standard_B1ms"
  # Sem "zone" fixa — a zone "1" não está disponível para esta assinatura em
  # northcentralus; deixando em branco o Azure escolhe uma zone disponível.
}

resource "azurerm_postgresql_flexible_server_database" "task_manager" {
  name      = "task_manager"
  server_id = azurerm_postgresql_flexible_server.db.id
  collation = "en_US.utf8"
  charset   = "UTF8"
}

# Libera o acesso a partir de serviços do Azure (o App Service não tem IP fixo).
resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_postgresql_flexible_server.db.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_linux_web_app" "app" {
  name                = "task-manager-app-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_service_plan.plan.location
  service_plan_id     = azurerm_service_plan.plan.id

  site_config {
    application_stack {
      # imagem publicada no Passo 2, via scripts/deploy-container-az.sh
      docker_image_name        = "task-manager:v1"
      docker_registry_url      = "https://${azurerm_container_registry.acr.login_server}"
      docker_registry_username = azurerm_container_registry.acr.admin_username
      docker_registry_password = azurerm_container_registry.acr.admin_password
    }
  }

  # Mesmas variáveis do serviço "app" no docker-compose.yml, apontando para o
  # Flexible Server acima em vez do container "postgres" local.
  app_settings = {
    WEBSITES_PORT = "3000"
    # Postgres Flexible Server exige SSL por padrão (diferente do postgres:15
    # local do docker-compose) — lib/db.js liga o SSL quando essa var é "true".
    DATABASE_SSL      = "true"
    DATABASE_HOST     = azurerm_postgresql_flexible_server.db.fqdn
    DATABASE_PORT     = "5432"
    DATABASE_NAME     = azurerm_postgresql_flexible_server_database.task_manager.name
    DATABASE_USER     = azurerm_postgresql_flexible_server.db.administrator_login
    DATABASE_PASSWORD = azurerm_postgresql_flexible_server.db.administrator_password
  }
}
