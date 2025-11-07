#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=========================================="
echo "🚀 Bookinfo アプリケーションのデプロイ"
echo "=========================================="

# Step 1: Bookinfo イメージを事前にロード
echo ""
echo "Step 1/3: Bookinfo イメージを Kind クラスターにロード中..."
echo "   (既にロード済みの場合はスキップされます)"

BOOKINFO_IMAGES=(
  "docker.io/istio/examples-bookinfo-productpage-v1:1.18.0"
  "docker.io/istio/examples-bookinfo-details-v1:1.18.0"
  "docker.io/istio/examples-bookinfo-ratings-v1:1.18.0"
  "docker.io/istio/examples-bookinfo-reviews-v1:1.18.0"
  "docker.io/istio/examples-bookinfo-reviews-v2:1.18.0"
  "docker.io/istio/examples-bookinfo-reviews-v3:1.18.0"
)

for image in "${BOOKINFO_IMAGES[@]}"; do
  echo "   ⏳ $image をプル中..."
  docker pull "$image" > /dev/null 2>&1 || true
  echo "   📦 Kind クラスターにロード中..."
  kind load docker-image "$image" --name kong-k8s > /dev/null 2>&1 || true
done

echo "   ✅ イメージロード完了!"

# Step 2: Bookinfo アプリケーションをデプロイ
echo ""
echo "Step 2/3: Bookinfo マイクロサービスのデプロイ..."
kubectl apply -f "$PROJECT_ROOT/bookinfo/bookinfo-deployment.yaml"

# デプロイメントの待機
echo ""
echo "⏳ Pods が Ready になるまで待機中..."
kubectl wait --for=condition=available --timeout=180s deployment/details-v1 -n bookinfo
kubectl wait --for=condition=available --timeout=180s deployment/ratings-v1 -n bookinfo
kubectl wait --for=condition=available --timeout=180s deployment/reviews-v1 -n bookinfo
kubectl wait --for=condition=available --timeout=180s deployment/reviews-v2 -n bookinfo
kubectl wait --for=condition=available --timeout=180s deployment/reviews-v3 -n bookinfo
kubectl wait --for=condition=available --timeout=180s deployment/productpage-v1 -n bookinfo

# Step 3: 動作確認
echo ""
echo "=========================================="
echo "✅ Bookinfo デプロイ完了!"
echo "=========================================="
echo ""
echo "📋 デプロイされたサービス:"
kubectl get services -l app -n bookinfo

echo ""
echo "📦 デプロイされた Pods:"
kubectl get pods -l app -n bookinfo

echo ""
echo "=========================================="
echo "🧪 動作確認コマンド:"
echo "=========================================="
echo ""
echo "# Productpage にアクセス (ポートフォワード):"
echo "kubectl port-forward svc/productpage 9080:9080 -n bookinfo"
echo "curl http://localhost:9080/productpage"
echo ""
echo "# または、ブラウザでアクセス:"
echo "open http://localhost:9080/productpage"
echo ""
