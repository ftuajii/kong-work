#!/bin/bash

set -e  # エラーが発生したら即座に終了

echo "🛑 Kong データプレーンを停止します..."

# Kongをアンインストール
echo ""
echo "📦 Kongをアンインストール中..."
helm uninstall my-kong -n kong || echo "⚠️  Kongは既に停止しています"

echo "⏳ Podの削除を待機中..."
kubectl wait --for=delete pod -l app.kubernetes.io/name=kong -n kong --timeout=60s || true

# 完了確認
echo ""
echo "✅ Kong停止完了!"
echo ""
echo "📊 状態確認:"
kubectl get pods -n kong
