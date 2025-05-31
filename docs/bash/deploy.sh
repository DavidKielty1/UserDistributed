#!/bin/bash

set -e

IMAGE_NAME="userdistributed-api:latest"
NAMESPACE="userdistributed"
PORT_LOCAL=8080
PORT_REMOTE=80

echo "1. Building Docker image..."
docker build -t $IMAGE_NAME -f ../../Dockerfile ../../

echo "2. Applying Kubernetes manifests..."
kubectl apply -f ../../Infra/k8s/namespace.yaml
kubectl apply -f ../../Infra/k8s/sqlserver.yaml
kubectl apply -f ../../Infra/k8s/redis.yaml
kubectl apply -f ../../Infra/k8s/api.yaml
kubectl apply -f ../../Infra/k8s/hpa.yaml

echo "3. Restarting API deployment..."
kubectl rollout restart deployment/userdistributed-api -n $NAMESPACE

echo "4. Waiting for API pods to be ready..."
kubectl wait --for=condition=ready pod -l app=userdistributed-api -n $NAMESPACE --timeout=180s || true

echo "5. Setting up port-forwarding (Ctrl+C to stop)..."
kubectl port-forward -n $NAMESPACE svc/userdistributed-api $PORT_LOCAL:$PORT_REMOTE

echo "Deployment complete! If port-forwarding did not start, run:"
echo "kubectl port-forward -n userdistributed svc/userdistributed-api 8080:80"