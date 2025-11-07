#!/bin/bash
set -e

echo "📊 監視スタック(Prometheus + Grafana)をセットアップします..."
echo ""

# 1. namespace作成
echo "📦 Step 1/4: monitoring namespaceを作成中..."
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# 2. kube-prometheus-stackインストール
echo ""
echo "📦 Step 2/4: kube-prometheus-stackをインストール中..."
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --values monitoring/prometheus-values.yaml \
  --wait

# 3. Kong ServiceMonitor作成
echo ""
echo "📦 Step 3/4: Kong ServiceMonitorを作成中..."
kubectl apply -f monitoring/kong-servicemonitor.yaml

# 4. ポートフォワード起動
echo ""
echo "📦 Step 4/4: ポートフォワードを起動中..."
# 既存のポートフォワードがあれば停止
pkill -f "port-forward.*grafana.*3000" 2>/dev/null || true
pkill -f "port-forward.*prometheus.*9090" 2>/dev/null || true
sleep 1

# ポートフォワード起動
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80 > /dev/null 2>&1 &
GRAFANA_PF_PID=$!

kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 > /dev/null 2>&1 &
PROMETHEUS_PF_PID=$!

# 完了確認
echo ""
echo "✅ セットアップ完了!"
echo ""
echo "📊 デプロイ状況:"
kubectl get pods -n monitoring

echo ""
echo "🌐 アクセス方法:"
echo "  Grafana:      http://localhost:3000 (admin/admin, PID: $GRAFANA_PF_PID)"
echo "  Prometheus:   http://localhost:9090 (PID: $PROMETHEUS_PF_PID)"
echo ""
echo "📈 Grafanaダッシュボード:"
echo "  - Kubernetes / Compute Resources / Cluster"
echo "  - Kubernetes / Compute Resources / Namespace (Pods)"
echo "  - Node Exporter / Nodes"
echo ""
echo "⏹  停止方法:"
echo "  kill $GRAFANA_PF_PID $PROMETHEUS_PF_PID"
echo "  # または pkill -f 'port-forward.*(grafana|prometheus)'"
