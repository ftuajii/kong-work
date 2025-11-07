#!/bin/bash
set -e

echo "🗑️  監視スタックを削除します..."

# ポートフォワードを停止
echo ""
echo "🔌 ポートフォワードを停止中..."
pkill -f "port-forward.*grafana.*3000" 2>/dev/null && echo "✅ Grafanaポートフォワード停止" || true
pkill -f "port-forward.*prometheus.*9090" 2>/dev/null && echo "✅ Prometheusポートフォワード停止" || true

# ServiceMonitor削除
echo ""
echo "📦 Kong ServiceMonitorを削除中..."
kubectl delete -f monitoring/kong-servicemonitor.yaml --ignore-not-found=true

# kube-prometheus-stack削除
echo "📦 kube-prometheus-stackを削除中..."
helm uninstall kube-prometheus-stack -n monitoring --ignore-not-found

# namespace削除
echo "📦 monitoring namespaceを削除中..."
kubectl delete namespace monitoring --ignore-not-found=true

echo ""
echo "✅ 削除完了!"
