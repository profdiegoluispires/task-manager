#!/bin/bash
set -e
RESOURCE_GROUP="rg-task-manager-container"
ACR_NAME="meuacrtaskmanager"

# Nome do App Service tem um sufixo aleatório (gerado pelo terraform, recurso
# random_string.suffix) para evitar colisão com o namespace global do Azure
# (*.azurewebsites.net) — busca dinamicamente em vez de fixar no script.
APP_NAME=$(az webapp list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv)

# 1. Builda a imagem localmente e envia via "docker push" — o ACR Tasks
#    (build remoto do "az acr build") esta bloqueado nesta assinatura
#    (TasksOperationsNotAllowed, comum em contas estudante/trial).
ACR_LOGIN_SERVER="$ACR_NAME.azurecr.io"

# Tag unica por deploy (timestamp) — o App Service so faz pull de uma imagem
# nova quando a REFERENCIA da imagem muda; reusar sempre "v1" faz o Azure so
# reiniciar o container ja em cache, servindo codigo antigo mesmo apos o push.
TAG=$(date +%Y%m%d%H%M%S)
IMAGE="$ACR_LOGIN_SERVER/task-manager:$TAG"

az acr login --name "$ACR_NAME"
docker build -f ./Dockerfile -t "$IMAGE" .
docker push "$IMAGE"

# 2. Aponta o App Service para a imagem recem-publicada (tag nova = pull garantido)
az webapp config container set --resource-group "$RESOURCE_GROUP" --name "$APP_NAME" \
  --container-image-name "$IMAGE"

# 3. Reinicia o App Service para aplicar a nova imagem
az webapp restart --resource-group "$RESOURCE_GROUP" --name "$APP_NAME"