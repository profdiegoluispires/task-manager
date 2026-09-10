#!/bin/bash
set -e
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"
IMAGE="$REGION-docker.pkg.dev/$PROJECT_ID/task-manager-repo/task-manager:latest"

gcloud auth configure-docker "$REGION-docker.pkg.dev" --quiet
docker build -f ./Dockerfile -t "$IMAGE" .
docker push "$IMAGE"
gcloud run deploy task-manager --image="$IMAGE" --region="$REGION" --allow-unauthenticated --project="$PROJECT_ID"