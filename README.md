# Kong Konnect データプレーン on Kind

## 概要

- **クラスター名**: `kong-k8s`
- **ノード構成**: 1 control-plane + 3 worker nodes
- **LoadBalancer**: MetalLB (IP プール: 172.21.255.200-250)
- **Kong データプレーン**: Konnect CP 接続用に構成済み
- **Kong イメージ**: `ghcr.io/ftuajii/bookinfo/kong-gateway:3.10` (ゴールデンイメージ)
- **オートスケーリング**: HPA 有効 (1-5 Pods, CPU 70%でスケール)
- **モニタリング**: Prometheus + Grafana (Kong メトリクス収集)

### スクリプト構成

このプロジェクトはモジュール化されたスクリプト構成を採用しています:

```
setup.sh (全体セットアップ - 6ステップ)
  ├─ 1. クラスター作成 (kind)
  ├─ 2. Helmリポジトリ追加
  ├─ 3. MetalLB インストール
  ├─ 4. Kong namespace & 証明書作成
  ├─ 5. start-kong.sh (3ステップ)
  │   ├─ Step 1: イメージロード
  │   ├─ Step 2: Kong デプロイ
  │   └─ Step 3: ポートフォワード起動 (8000)
  └─ 6. setup-monitoring.sh (4ステップ)
      ├─ Step 1: Namespace作成
      ├─ Step 2: kube-prometheus-stack インストール
      ├─ Step 3: ServiceMonitor作成
      └─ Step 4: ポートフォワード起動 (3000, 9090)

cleanup.sh (全体削除)
  ├─ cleanup-monitoring.sh (ポートフォワード停止 + モニタリング削除)
  ├─ stop-kong.sh (ポートフォワード停止 + Kong DP 削除)
  └─ クラスター削除

個別管理スクリプト:
  ├─ start-kong.sh         # Kong DP 起動 (3ステップ)
  ├─ stop-kong.sh          # Kong DP 停止 + ポートフォワード停止
  ├─ redeploy-kong.sh      # Kong DP 再デプロイ
  ├─ setup-monitoring.sh   # モニタリング起動 (4ステップ)
  └─ cleanup-monitoring.sh # モニタリング削除 + ポートフォワード停止
```

**設計原則:**

- ✅ **モジュラー設計**: 各コンポーネントが独立したスクリプトで管理
- ✅ **単一責任**: 各スクリプトが自身のリソースとポートフォワードを管理
- ✅ **段階的実行**: 各スクリプト内でステップ表示により進捗を可視化
- ✅ **冪等性**: 既存リソースがある場合は適切にハンドリング
- ✅ **クリーンアップ**: 削除スクリプトがポートフォワードも自動停止

## 前提条件

- ✅ Docker Engine 起動済み（Docker Desktop、Colima、Podman など）
- ✅ kubectl (v1.34.1+)
- ✅ Helm 3 (v3.18.4+)
- ✅ kind (v1.34.0+)
- ✅ curl (動作確認用)
- ✅ Konnect 証明書 (`kong/secrets/tls.crt`, `tls.key`)

## クイックスタート

```bash
# 全環境構築（約5分）
./scripts/setup.sh

# → 自動的にポートフォワードが開始されます:
#   - Kong Proxy:  http://localhost:8000
#   - Grafana:     http://localhost:3000 (admin/admin)
#   - Prometheus:  http://localhost:9090

# 動作確認
curl http://localhost:8000

# Kong 個別管理
./scripts/start-kong.sh            # Kong DP起動 (3ステップ)
./scripts/stop-kong.sh             # Kong DP停止 + ポートフォワード停止
./scripts/redeploy-kong.sh         # Kong DP再デプロイ

# モニタリング 個別管理
./scripts/setup-monitoring.sh      # モニタリング起動 (4ステップ)
./scripts/cleanup-monitoring.sh    # モニタリング削除 + ポートフォワード停止

# 全環境削除
./scripts/cleanup.sh
```

**スクリプト実行フロー:**

```
setup.sh (6ステップ)
  ↓
├─ Step 1-4: 基盤構築 (Cluster, Helm, MetalLB, Namespace)
├─ Step 5: start-kong.sh
│   ├─ Kong イメージロード
│   ├─ Kong デプロイ
│   └─ ポートフォワード起動 (8000) ← 自動
└─ Step 6: setup-monitoring.sh
    ├─ Namespace作成
    ├─ kube-prometheus-stack インストール
    ├─ ServiceMonitor作成
    └─ ポートフォワード起動 (3000, 9090) ← 自動
```

## アーキテクチャ

### Kubernetes 構成

```
Cluster: kong-k8s
  ├─ Node: control-plane (管理ノード)
  │   ├─ Kubernetes管理コンポーネント
  │   ├─ MetalLB Speaker (DaemonSet)
  │   └─ Node Exporter (DaemonSet)
  │
  ├─ Node: worker (ワーカー1)
  │   ├─ Kong DP Pods (HPA: 1-5個で分散配置)
  │   ├─ MetalLB Speaker (DaemonSet)
  │   └─ Node Exporter (DaemonSet)
  │
  ├─ Node: worker2 (ワーカー2)
  │   ├─ Kong DP Pods (HPA: 1-5個で分散配置)
  │   ├─ MetalLB Speaker (DaemonSet)
  │   └─ Node Exporter (DaemonSet)
  │
  └─ Node: worker3 (ワーカー3)
      ├─ Kong DP Pods (HPA: 1-5個で分散配置)
      ├─ MetalLB Speaker (DaemonSet)
      └─ Node Exporter (DaemonSet)

Namespace: metallb-system
  ├─ MetalLB Controller (Deployment, 1レプリカ)
  └─ MetalLB Speaker (DaemonSet, 全ノードで稼働)

Namespace: monitoring
  ├─ Prometheus (StatefulSet)
  ├─ Grafana (Deployment)
  ├─ Alertmanager (StatefulSet)
  ├─ kube-state-metrics (Deployment)
  ├─ Prometheus Operator (Deployment)
  └─ Node Exporter (DaemonSet, 全ノードで稼働)
```

### ネットワーク

- **ClusterIP**: 内部通信用
- **LoadBalancer IP**: 172.21.255.200 (MetalLB 管理)
- **ホストアクセス**: `kubectl port-forward` (kind の制限により直接アクセス不可)

## Konnect 証明書の設定

1. Konnect UI から証明書をダウンロード
2. `kong/secrets/`に配置
   ```
   kong/secrets/
   ├── tls.crt
   └── tls.key
   ```
3. `./scripts/setup.sh`または`./scripts/start-kong.sh`で自動的に Secret が作成されます

## ファイル構成

```
.
├── infrastructure/           # Kubernetes基盤設定
│   ├── kind-config.yaml      # kindクラスター設定(3ノード)
│   └── metallb-config.yaml   # MetalLB IPアドレスプール
├── kong/                     # Kong設定
│   ├── values.yaml           # Kong Helm values (Konnect接続, HPA設定)
│   ├── secrets/              # Konnect証明書 (Git除外)
│   │   ├── tls.crt
│   │   └── tls.key
│   └── configs/              # Kong設定ファイル (今後追加)
│       └── README.md
├── monitoring/               # モニタリング設定
│   ├── prometheus-values.yaml    # Prometheus+Grafana設定
│   └── kong-servicemonitor.yaml  # KongメトリクスServiceMonitor
├── scripts/                  # 自動化スクリプト
│   ├── setup.sh              # ⭐ 全体セットアップ (クラスター+Kong+モニタリング)
│   ├── cleanup.sh            # ⭐ 全体削除 (モニタリング+Kong+クラスター)
│   ├── start-kong.sh         # Kong DP起動
│   ├── stop-kong.sh          # Kong DP停止
│   ├── redeploy-kong.sh      # Kong DP再デプロイ (stop→start)
│   ├── setup-monitoring.sh   # モニタリングセットアップ
│   └── cleanup-monitoring.sh # モニタリング削除
├── .gitignore
└── README.md
```

## スクリプト説明

### `scripts/setup.sh` ⭐ メインスクリプト

**環境全体を自動構築します。**

**処理内容:**

1. kind クラスター作成 (4 ノード: 1 control-plane + 3 workers)
2. Helm リポジトリ追加 (kong, metallb, prometheus-community)
3. MetalLB インストール & 設定 (LoadBalancer 実装)
4. Kong namespace & 証明書 Secret 作成
5. **Kong DP デプロイ** (`start-kong.sh` を呼び出し)
6. **モニタリングスタックデプロイ** (`setup-monitoring.sh` を呼び出し)
7. **ポートフォワード自動開始** (Kong:8000, Grafana:3000, Prometheus:9090)

**所要時間:** 約 5 分

**デプロイされるもの:**

- ✅ Kubernetes クラスター (kind)
- ✅ LoadBalancer (MetalLB)
- ✅ Kong Data Plane (HPA 有効)
- ✅ Prometheus + Grafana + Alertmanager
- ✅ Node Exporter × 4
- ✅ Kong ServiceMonitor
- ✅ ポートフォワード (バックグラウンドプロセス)

**自動的にアクセス可能:**

- http://localhost:8000 (Kong Proxy)
- http://localhost:3000 (Grafana, admin/admin)
- http://localhost:9090 (Prometheus)

---

### `scripts/cleanup.sh` ⭐ メインスクリプト

**環境全体を削除します。**

**処理内容:**

1. **モニタリングスタック削除** (`cleanup-monitoring.sh` を呼び出し)
2. **Kong DP 削除** (`stop-kong.sh` を呼び出し)
3. Kong namespace 削除
4. MetalLB Helm リリース削除
5. metallb-system namespace 削除
6. kind クラスター削除

**所要時間:** 約 15 秒

---

### `scripts/start-kong.sh`

**Kong DP のみを起動します。**

**処理内容:**

1. kong namespace 存在確認（なければ作成）
2. 証明書 Secret 作成（必要な場合）
3. Kong イメージロード
4. Kong Helm デプロイ (HPA 有効)

**使用場面:**

- stop 後の再起動
- Kong DP のみを個別デプロイ

**所要時間:** 約 1 分

---

### `scripts/stop-kong.sh`

**Kong DP のみを停止します。**

**処理内容:**

1. Kong Helm リリースアンインストール
2. Pod 削除待機

**使用場面:**

- 一時停止
- メンテナンス前
- Kong DP のみを個別削除

**所要時間:** 約 10 秒

**注意:** kong namespace は削除されません（再起動可能な状態）

---

### `scripts/redeploy-kong.sh`

**Kong DP を再デプロイします** (stop→start)。

**使用場面:**

- `kong/values.yaml` 変更後
- 設定初期化
- トラブルシューティング

**所要時間:** 約 1-2 分

---

### `scripts/setup-monitoring.sh`

**Prometheus + Grafana モニタリングスタックをセットアップします。**

**処理内容:**

1. monitoring namespace 作成
2. kube-prometheus-stack インストール (Prometheus, Grafana, Alertmanager)
3. Kong ServiceMonitor 作成

**使用場面:**

- モニタリングのみを個別デプロイ
- モニタリングの再構築

**所要時間:** 約 2 分

---

### `scripts/cleanup-monitoring.sh`

**モニタリングスタックを削除します。**

**処理内容:**

1. Kong ServiceMonitor 削除
2. kube-prometheus-stack アンインストール
3. monitoring namespace 削除

**使用場面:**

- モニタリングのみを個別削除
- モニタリングの再構築前

**所要時間:** 約 10 秒

---

## モニタリング (Prometheus + Grafana)

### セットアップ

```bash
# setup.shで自動的にデプロイされます
./scripts/setup.sh

# または個別にセットアップ
./scripts/setup-monitoring.sh
```

**インストールされるコンポーネント:**

- Prometheus (メトリクス収集)
- Grafana (可視化ダッシュボード)
- Alertmanager (アラート管理)
- Node Exporter × 4 (各ノードのメトリクス)
- kube-state-metrics (Kubernetes リソース監視)
- Kong ServiceMonitor (Kong 専用メトリクス収集)

### アクセス方法

**Grafana:**

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
# http://localhost:3000
# ユーザー名: admin
# パスワード: admin
```

**Prometheus:**

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# http://localhost:9090
```

### Kong メトリクス

Grafana で利用可能な Kong メトリクス:

**基本メトリクス:**

- `kong_control_plane_connected` - Konnect CP 接続状態
- `kong_datastore_reachable` - データストア接続状態
- `kong_nginx_requests_total` - Nginx リクエスト総数

**HTTP メトリクス (Route と Service が設定されている場合):**

- `kong_http_requests_total` - HTTP リクエスト総数 (Service/Route 別)
- `kong_bandwidth_bytes` - 帯域幅使用量
- `kong_kong_latency_ms_*` - レイテンシ (ヒストグラム)

**使用例:**

```promql
# リクエストレート
sum(rate(kong_http_requests_total[1m]))

# Service別のリクエストレート
sum(rate(kong_http_requests_total[1m])) by (exported_service)

# HTTPステータスコード別
sum(rate(kong_http_requests_total[1m])) by (code)
```

### Grafana ダッシュボード

推奨ダッシュボード:

1. **Kong (official)** - Kong 公式ダッシュボード (ID: 7424)
2. **Kubernetes / Compute Resources / Cluster** - クラスタ全体のリソース
3. **Kubernetes / Compute Resources / Namespace (Pods)** - Pod 別リソース
4. **Node Exporter / Nodes** - ノード詳細メトリクス

### 重要な注意事項

**Kong HTTP メトリクスの前提条件:**

1. Konnect CP で Prometheus Plugin を有効化
2. Prometheus Plugin 設定で以下を ON にする:
   - `status_code_metrics: ON`
   - `latency_metrics: ON`
   - `bandwidth_metrics: ON`
3. **Route と Service が設定されている必要あり**

Route と Service が未設定の場合、基本メトリクス(`kong_control_plane_connected`など)のみ利用可能です。

### 削除

```bash
./scripts/cleanup-monitoring.sh
```

## 管理コマンド

### ポートフォワード管理

各スクリプトが自身のポートフォワードを管理する設計になっています。

**自動起動:**

| スクリプト            | ポート | 対象サービス | ステップ |
| --------------------- | ------ | ------------ | -------- |
| `start-kong.sh`       | 8000   | Kong Proxy   | Step 3/3 |
| `setup-monitoring.sh` | 3000   | Grafana      | Step 4/4 |
| `setup-monitoring.sh` | 9090   | Prometheus   | Step 4/4 |

**自動停止:**

| スクリプト              | 停止内容                                                  |
| ----------------------- | --------------------------------------------------------- |
| `stop-kong.sh`          | Kong Proxy (8000) のポートフォワード停止                  |
| `cleanup-monitoring.sh` | Grafana (3000) + Prometheus (9090) のポートフォワード停止 |
| `cleanup.sh`            | 全てのポートフォワード停止 (上記 2 つを呼び出し)          |

**手動操作:**

```bash
# 個別停止
pkill -f "port-forward.*kong.*8000"        # Kong Proxy
pkill -f "port-forward.*grafana.*3000"     # Grafana
pkill -f "port-forward.*prometheus.*9090"  # Prometheus

# 一括停止
pkill -f port-forward

# 手動起動
kubectl port-forward -n kong svc/my-kong-kong-proxy 8000:80 &
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80 &
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &

# プロセス確認
ps aux | grep port-forward
```

**トラブルシューティング:**

```bash
# ポートが既に使用されている場合
lsof -i :8000  # ポート8000を使っているプロセスを確認
kill <PID>     # 該当プロセスを停止

# ポートフォワードが起動しない場合
kubectl get svc -n kong           # サービスが存在するか確認
kubectl get svc -n monitoring     # サービスが存在するか確認
kubectl get pods -n kong          # Podが Running か確認
kubectl get pods -n monitoring    # Podが Running か確認
```

---

### 状態確認

```bash
# クラスター確認
kubectl get nodes
kubectl get pods -A

# Kong確認
kubectl get pods,svc,hpa -n kong

# MetalLB確認
kubectl get pods -n metallb-system
kubectl get ipaddresspool,l2advertisement -n metallb-system
```

### Kong 設定変更

```bash
# values.yaml編集後
./scripts/redeploy-kong.sh

# または直接Helmアップグレード
helm upgrade my-kong kong/kong -n kong --values kong/values.yaml
```

### HPA (オートスケーリング) 確認

```bash
# HPA状態確認
kubectl get hpa -n kong

# リアルタイム監視
kubectl get hpa -n kong -w

# 手動スケール (テスト用)
kubectl scale deployment my-kong-kong -n kong --replicas=3
```

## 環境の完全復元

### 自動復元（推奨）⭐

```bash
# 全削除 → 全再構築を一括実行
./scripts/cleanup.sh && ./scripts/setup.sh
```

**所要時間:** 約 5 分 15 秒 (削除 15 秒 + セットアップ 5 分)

**復元されるもの:**

- ✅ Kubernetes クラスター (kind)
- ✅ MetalLB (LoadBalancer)
- ✅ Kong Data Plane
- ✅ Prometheus + Grafana

---

### 個別の復元

```bash
# Kong DPのみ復元
./scripts/stop-kong.sh && ./scripts/start-kong.sh

# モニタリングのみ復元
./scripts/cleanup-monitoring.sh && ./scripts/setup-monitoring.sh
```

---

### 手動復元（参考）

自動スクリプトを使わず、手動で復元する手順:

```bash
# 1. モニタリング削除
kubectl delete -f monitoring/kong-servicemonitor.yaml
helm uninstall kube-prometheus-stack -n monitoring
kubectl delete namespace monitoring

# 2. Kong DP削除
helm uninstall my-kong -n kong
kubectl delete namespace kong

# 3. MetalLB削除
helm uninstall metallb -n metallb-system
kubectl delete namespace metallb-system

# 4. クラスター削除
kind delete cluster --name kong-k8s

# 5. Helmリポジトリ追加（初回のみ）
helm repo add kong https://charts.konghq.com
helm repo add metallb https://metallb.github.io/metallb
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# 3. MetalLBを復元
helm install metallb metallb/metallb -n metallb-system --create-namespace
kubectl wait --namespace metallb-system --for=condition=ready pod --selector=app.kubernetes.io/name=metallb --timeout=90s
kubectl apply -f infrastructure/metallb-config.yaml

# 4. namespaceとSecretを作成
kubectl create namespace kong
kubectl create secret tls kong-cluster-cert -n kong \
  --cert=kong/secrets/tls.crt \
  --key=kong/secrets/tls.key

# 5. Kongイメージロード
docker pull ghcr.io/ftuajii/bookinfo/kong-gateway:3.10
kind load docker-image ghcr.io/ftuajii/bookinfo/kong-gateway:3.10 --name kong-k8s

# 6. Kongをデプロイ
helm install my-kong kong/kong -n kong --skip-crds --values kong/values.yaml
```

## トラブルシューティング

### Kong Pod が起動しない

```bash
# Pod状態確認
kubectl get pods -n kong
kubectl describe pod -n kong <pod-name>

# ログ確認
kubectl logs -n kong <pod-name>

# Probe設定確認 (initialDelaySeconds: 30秒)
kubectl get pod -n kong <pod-name> -o yaml | grep -A 10 Probe
```

### HPA が機能しない

```bash
# HPA状態確認
kubectl get hpa -n kong
kubectl describe hpa my-kong-kong -n kong

# Metrics Server確認 (kindにはデフォルトで無い)
kubectl top nodes
kubectl top pods -n kong
```

**注意:** kind は Metrics Server が含まれていないため、CPU 使用率が`<unknown>`と表示されます。実際のスケーリングテストには Metrics Server のインストールが必要です。

### LoadBalancer IP が割り当てられない

```bash
# MetalLBの状態確認
kubectl get pods -n metallb-system
kubectl get ipaddresspool -n metallb-system
```

### 外部アクセスできない

kind クラスターの MetalLB IP (`172.21.255.200`) はホストから直接アクセス不可。

**解決策:**

```bash
# port-forwardを使用
kubectl port-forward -n kong svc/my-kong-kong-proxy 8000:80
curl http://localhost:8000
```

## API Spec 公開 (Dev Portal)

Kong Konnect Dev Portal に API 仕様を公開する機能を提供しています。

### クイックスタート

```bash
# 環境変数を設定
export KONNECT_TOKEN='your-konnect-token'
export API_PRODUCT_ID='your-api-product-id'
export VERSION_ID='your-version-id'

# API Specを公開
./scripts/publish-api-spec.sh

# Version も公開状態にする場合
PUBLISH_VERSION=true ./scripts/publish-api-spec.sh
```

### GitHub Actions で自動公開

1. GitHub Secrets を設定:

   - `KONNECT_TOKEN`
   - `API_PRODUCT_ID`
   - `VERSION_ID`

2. `kong/specs/openapi.yaml` を変更してプッシュすると自動的に公開されます

3. 手動実行も可能: Actions → "Publish API Spec to Konnect Dev Portal" → Run workflow

### 詳細ドキュメント

詳細な使い方、トラブルシューティング、必要な情報の取得方法については、以下のドキュメントを参照してください:

📚 **[API Spec 公開ガイド](docs/API_SPEC_PUBLISHING.md)**
