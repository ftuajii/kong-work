#!/bin/bash

set -e

# スクリプトのディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🗑️  Kong Konnect環境を削除中..."
echo "   (Bookinfo + Kong DP + モニタリング + クラスター基盤)"
echo ""

# 1. Bookinfo アプリケーション削除 (個別スクリプト呼び出し)
echo "📦 Bookinfo アプリケーションを削除中..."
"$SCRIPT_DIR/cleanup-bookinfo.sh" 2>/dev/null || echo "  (Bookinfoは存在しません)"

# 2. Kong DP削除 (個別スクリプト呼び出し)
echo ""
echo "📦 Kong DPを削除中..."
"$SCRIPT_DIR/stop-kong.sh" 2>/dev/null || echo "  (Kong DPは存在しません)"

# 3. モニタリングスタック削除 (個別スクリプト呼び出し)
echo ""
echo "📦 モニタリングスタックを削除中..."
"$SCRIPT_DIR/cleanup-monitoring.sh" 2>/dev/null || echo "  (モニタリングは存在しません)"

# 4. Kong namespace削除
echo ""
echo "📦 Kong namespaceを削除中..."
kubectl delete namespace kong --force --grace-period=0 2>/dev/null || echo "  (kong namespaceは存在しません)"

# 5. Bookinfo namespace削除
echo ""
echo "📦 Bookinfo namespaceを削除中..."
kubectl delete namespace bookinfo --force --grace-period=0 2>/dev/null || echo "  (bookinfo namespaceは存在しません)"

# 6. MetalLB削除
echo ""
echo "📦 MetalLBを削除中..."
helm uninstall metallb -n metallb-system 2>/dev/null || echo "  (metallbは存在しません)"
kubectl delete namespace metallb-system --force --grace-period=0 2>/dev/null || echo "  (metallb-system namespaceは存在しません)"

# 7. kindクラスター削除
echo ""
echo "📦 kindクラスターを削除中..."
kind delete cluster --name kong-k8s 2>/dev/null || echo "  (クラスターは存在しません)"

echo ""
echo "✅ 削除完了!"
