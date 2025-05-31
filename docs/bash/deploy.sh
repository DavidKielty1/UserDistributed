#!/bin/bash

set -e

IMAGE_NAME="userdistributed-api:latest"
NAMESPACE="userdistributed"
PORT_LOCAL=8080
PORT_REMOTE=80

echo "1. Building Docker image..."
docker build -t $IMAGE_NAME -f ../../Dockerfile ../../

echo "2. Cleaning up any existing NGINX Ingress resources..."
helm uninstall ingress-nginx 2>/dev/null || true
kubectl delete clusterrole ingress-nginx 2>/dev/null || true
kubectl delete clusterrolebinding ingress-nginx 2>/dev/null || true
kubectl delete validatingwebhookconfiguration ingress-nginx-admission 2>/dev/null || true
kubectl delete namespace ingress-nginx 2>/dev/null || true
kubectl delete ingressclass nginx 2>/dev/null || true
kubectl delete ingressclass traefik 2>/dev/null || true

echo "3. Installing NGINX Ingress Controller..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --set controller.service.type=NodePort \
  --set controller.minReadySeconds=30 \
  --set controller.progressDeadlineSeconds=600 \
  --wait

echo "4. Applying Kubernetes manifests..."
kubectl apply -f ../../Infra/k8s/namespace.yaml
kubectl apply -f ../../Infra/k8s/sqlserver.yaml
kubectl apply -f ../../Infra/k8s/redis.yaml
kubectl apply -f ../../Infra/k8s/api.yaml
kubectl apply -f ../../Infra/k8s/hpa.yaml

# Ingresses
echo "5. Applying Ingress manifests..."
kubectl apply -f ../../Infra/k8s/ingress.yaml
kubectl apply -f ../../Infra/monitoring/ingress.yaml

echo "6. Restarting API deployment..."
kubectl rollout restart deployment/userdistributed-api -n $NAMESPACE

echo "7. Getting NGINX Ingress NodePort..."
NODE_PORT=$(kubectl get svc -n default ingress-nginx-controller -o jsonpath='{.spec.ports[0].nodePort}')

helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --set prometheus.prometheusSpec.maximumStartupDurationSeconds=600

echo "Deployment complete!"
echo "You can access your services at:"
echo "API:                http://localhost:$NODE_PORT/api"
echo "Grafana:            http://localhost:$NODE_PORT/grafana"
echo "Loki:               http://localhost:$NODE_PORT/loki"
echo "Prometheus:         http://localhost:$NODE_PORT/prometheus"
echo "Prometheus-Grafana: http://localhost:$NODE_PORT/prom-grafana"