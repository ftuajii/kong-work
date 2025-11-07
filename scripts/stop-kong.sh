#!/bin/bash

set -e  # エラーが発生したら即座に終了

echo "🛑 Kong データプレーンを停止します..."

# ポートフォワードを停止
echo ""
echo "🔌 ポートフォワードを停止中..."
pkill -f "port-forward.*kong.*8000" 2>/dev/null && echo "✅ Kong Proxyポートフォワード停止" || echo "ℹ️  ポートフォワードは起動していません"

# Kongをアンインストール
echo ""
echo "📦 Kongをアンインストール中..."
helm uninstall my-kong -n kong || echo "⚠️  Kongは既に停止しています"

echo "⏳ Podの削除を待機中..."
kubectl wait --for=delete pod -l app.kubernetes.io/name=kong -n kong --timeout=60s 2>/dev/null || true

# 完了確認
echo ""
echo "✅ Kong停止完了!"
echo ""
echo "ℹ️  Note: kong namespaceは削除されていません（再起動可能）"
echo "    完全削除する場合: kubectl delete namespace kong"
