#!/bin/bash

set -e  # エラーが発生したら即座に終了

# スクリプトのディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🚀 Kong Konnect環境のセットアップを開始します..."
echo "   (クラスター基盤 + Kong DP + モニタリング)"
echo ""

# 1. kindクラスター作成
echo "📦 Step 1/6: kindクラスターを作成中..."
kind create cluster --name kong-k8s --config "$ROOT_DIR/infrastructure/kind-config.yaml"

# 2. Helmリポジトリ追加
echo ""
echo "📦 Step 2/6: Helmリポジトリを追加中..."
helm repo add kong https://charts.konghq.com 2>/dev/null || true
helm repo add metallb https://metallb.github.io/metallb 2>/dev/null || true
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
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

# 5. Kong DPデプロイ (個別スクリプト呼び出し)
echo ""
echo "📦 Step 5/6: Kong DPをデプロイ中..."
"$SCRIPT_DIR/start-kong.sh"

# 6. モニタリングスタックデプロイ (個別スクリプト呼び出し)
echo ""
echo "📦 Step 6/6: モニタリングスタック(Prometheus + Grafana)をセットアップ中..."
"$SCRIPT_DIR/setup-monitoring.sh"

# 完了確認
echo ""
echo "✅ 全体セットアップ完了!"
echo ""
echo "📊 デプロイ状況:"
echo ""
echo "【Kong DP】"
kubectl get pods,svc -n kong
echo ""
echo "【モニタリング】"
kubectl get pods -n monitoring

echo ""
echo "🌐 アクセス可能なサービス:"
echo "  ✅ Kong Proxy:    http://localhost:8000"
echo "  ✅ Grafana:       http://localhost:3000 (admin/admin)"
echo "  ✅ Prometheus:    http://localhost:9090"
echo ""
echo "📝 ポートフォワードは各個別スクリプトで自動起動されています"
echo "   停止: pkill -f port-forward"
