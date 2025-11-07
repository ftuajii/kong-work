#!/bin/bash

set -e  # エラーが発生したら即座に終了

# スクリプトのディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "▶️  Kong データプレーンを起動します..."
echo ""

# namespaceが存在するか確認
if ! kubectl get namespace kong &> /dev/null; then
    echo "⚠️  kong namespaceが存在しません。作成します..."
    kubectl create namespace kong
    
    # 証明書Secretも作成
    if [ -f "$ROOT_DIR/kong/secrets/tls.crt" ] && [ -f "$ROOT_DIR/kong/secrets/tls.key" ]; then
        kubectl create secret tls kong-cluster-cert -n kong \
          --cert="$ROOT_DIR/kong/secrets/tls.crt" \
          --key="$ROOT_DIR/kong/secrets/tls.key"
    else
        echo "❌ エラー: 証明書ファイルが見つかりません"
        echo "   $ROOT_DIR/kong/secrets/tls.crt"
        echo "   $ROOT_DIR/kong/secrets/tls.key"
        exit 1
    fi
    echo ""
fi

# 1. Kongイメージロード
echo "📦 Step 1/3: Kongイメージをロード中..."
docker pull ghcr.io/ftuajii/bookinfo/kong-gateway:3.10
kind load docker-image ghcr.io/ftuajii/bookinfo/kong-gateway:3.10 --name kong-k8s

# 2. Kongをデプロイ
echo ""
echo "📦 Step 2/3: Kongをデプロイ中..."
helm install my-kong kong/kong -n kong --skip-crds --values "$ROOT_DIR/kong/values.yaml"

echo ""
echo "⏳ Kong Podの起動を待機中..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kong -n kong --timeout=120s

# 3. ポートフォワード起動
echo ""
echo "📦 Step 3/3: ポートフォワードを起動中..."
# 既存のポートフォワードがあれば停止
pkill -f "port-forward.*kong.*8000" 2>/dev/null || true
sleep 1

# ポートフォワード起動
kubectl port-forward -n kong svc/my-kong-kong-proxy 8000:80 > /dev/null 2>&1 &
KONG_PF_PID=$!

# 完了確認
echo ""
echo "✅ Kong起動完了!"
echo ""
echo "📊 デプロイ状況:"
kubectl get pods -n kong
kubectl get svc -n kong

echo ""
echo "🌐 アクセス方法:"
echo "  Kong Proxy:   http://localhost:8000 (PID: $KONG_PF_PID)"
echo ""
echo "⏹  停止方法:"
echo "  kill $KONG_PF_PID  # または pkill -f 'port-forward.*kong.*8000'"
