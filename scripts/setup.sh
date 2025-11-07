#!/bin/bash

set -e  # エラーが発生したら即座に終了

# スクリプトのディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🚀 Kong Konnect環境のセットアップを開始します..."

# 1. kindクラスター作成
echo ""
echo "📦 Step 1/6: kindクラスターを作成中..."
kind create cluster --name kong-k8s --config "$ROOT_DIR/infrastructure/kind-config.yaml"

# 2. Helmリポジトリ追加
echo ""
echo "📦 Step 2/6: Helmリポジトリを追加中..."
helm repo add kong https://charts.konghq.com 2>/dev/null || true
helm repo add metallb https://metallb.github.io/metallb 2>/dev/null || true
helm repo update

# 3. MetalLBインストール
echo ""
echo "📦 Step 3/6: MetalLBをインストール中..."
helm install metallb metallb/metallb -n metallb-system --create-namespace

echo "⏳ MetalLBの起動を待機中..."
kubectl wait --namespace metallb-system --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=90s
sleep 10  # webhook serviceの起動を待つ

kubectl apply -f "$ROOT_DIR/infrastructure/metallb-config.yaml"

# 4. Kong namespace と証明書作成
echo ""
echo "📦 Step 4/6: Kong namespaceと証明書を作成中..."
kubectl create namespace kong
kubectl create secret tls kong-cluster-cert -n kong \
  --cert="$ROOT_DIR/kong/secrets/tls.crt" \
  --key="$ROOT_DIR/kong/secrets/tls.key"

# 5. Kongイメージロード
echo ""
echo "📦 Step 5/6: Kongイメージをロード中..."
docker pull ghcr.io/ftuajii/bookinfo/kong-gateway:3.10
kind load docker-image ghcr.io/ftuajii/bookinfo/kong-gateway:3.10 --name kong-k8s

# 6. Kongデプロイ
echo ""
echo "📦 Step 6/6: Kongをデプロイ中..."
helm install my-kong kong/kong -n kong --skip-crds --values "$ROOT_DIR/kong/values.yaml"

echo ""
echo "⏳ Kong Podの起動を待機中..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kong -n kong --timeout=120s

# 完了確認
echo ""
echo "✅ セットアップ完了!"
echo ""
echo "📊 デプロイ状況:"
kubectl get pods -n kong
kubectl get svc -n kong

echo ""
echo "🌐 アクセス方法:"
echo "  kubectl port-forward -n kong svc/my-kong-kong-proxy 8000:80"
echo "  curl http://localhost:8000"
