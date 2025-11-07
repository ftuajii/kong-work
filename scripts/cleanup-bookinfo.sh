#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=========================================="
echo "🗑️  Bookinfo アプリケーションの削除"
echo "=========================================="

# Step 1: Bookinfo アプリケーションの削除
echo ""
echo "Step 1: Bookinfo マイクロサービスを削除..."
kubectl delete -f "$PROJECT_ROOT/bookinfo/bookinfo-deployment.yaml" --ignore-not-found=true

echo ""
echo "=========================================="
echo "✅ Bookinfo 削除完了!"
echo "=========================================="
