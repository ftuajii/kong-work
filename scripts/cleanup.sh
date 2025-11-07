#!/bin/bash

set -e

echo "🗑️  Kong Konnect環境を削除中..."

# Helmリリース削除
echo "📦 Helmリリースを削除中..."
helm uninstall my-kong -n kong 2>/dev/null || echo "  (my-kongは存在しません)"
helm uninstall metallb -n metallb-system 2>/dev/null || echo "  (metallbは存在しません)"

# Namespace削除
echo "📦 Namespaceを削除中..."
kubectl delete namespace kong metallb-system --force --grace-period=0 2>/dev/null || echo "  (namespaceは存在しません)"

# kindクラスター削除
echo "📦 kindクラスターを削除中..."
kind delete cluster --name kong-k8s 2>/dev/null || echo "  (クラスターは存在しません)"

echo ""
echo "✅ 削除完了!"
