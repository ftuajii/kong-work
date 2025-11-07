#!/bin/bash

set -e  # エラーが発生したら即座に終了

# スクリプトのディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "▶️  Kong データプレーンを起動します..."

# 1. Kongイメージロード（最新イメージを使う場合）
echo ""
echo "📦 Step 1/2: Kongイメージをロード中..."
docker pull ghcr.io/ftuajii/bookinfo/kong-gateway:3.10
kind load docker-image ghcr.io/ftuajii/bookinfo/kong-gateway:3.10 --name kong-k8s

# 2. Kongをデプロイ
echo ""
echo "📦 Step 2/2: Kongをデプロイ中..."
helm install my-kong kong/kong -n kong --skip-crds --values "$ROOT_DIR/kong/values.yaml"

echo ""
echo "⏳ Kong Podの起動を待機中..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kong -n kong --timeout=120s

# 完了確認
echo ""
echo "✅ Kong起動完了!"
echo ""
echo "📊 デプロイ状況:"
kubectl get pods -n kong
kubectl get svc -n kong

echo ""
echo "🌐 アクセス方法:"
echo "  kubectl port-forward -n kong svc/my-kong-kong-proxy 8000:80"
echo "  curl http://localhost:8000"
