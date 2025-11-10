# Kong Konnect + Bookinfo on Kubernetes (Kind)

## 概要

このプロジェクトは、Kong Konnect のデータプレーン(DP)と Bookinfo サンプルアプリケーションを Kubernetes (Kind) 上にデプロイし、API ゲートウェイとして Kong を活用する環境を提供します。

📊 **[システムアーキテクチャ図を見る](ARCHITECTURE.md)**

### 主要コンポーネント

- **クラスター**: Kind (1 control-plane + 3 workers)
- **LoadBalancer**: MetalLB (172.21.255.200-250)
- **Kong Gateway**: v3.10 (Data Plane モード、Konnect CP 接続)
- **Bookinfo**: Istio サンプルアプリケーション (productpage のみを Kong で管理)
- **モニタリング**: kube-prometheus-stack (Prometheus + Grafana)
- **オートスケーリング**: HPA 有効 (1-5 Pods, CPU 70%)

### アーキテクチャ

```
┌─────────────────────────────────────────────────────────┐
│ Kong Konnect (SaaS)                                     │
│  - Control Plane (CP)                                   │
│  - Dev Portal (API仕様公開)                             │
└─────────────────────┬───────────────────────────────────┘
                      │ mTLS
                      ↓
┌─────────────────────────────────────────────────────────┐
│ Kubernetes Cluster (Kind)                               │
│                                                          │
│  ┌──────────────────────────────────────────────────┐  │
│  │ Kong Data Plane (namespace: kong)                │  │
│  │  - ServiceMonitor (Prometheusメトリクス収集)    │  │
│  │  - HPA (1-5 Pods)                                │  │
│  │  - MetalLB LoadBalancer (172.21.255.200)         │  │
│  └──────────────────────────────────────────────────┘  │
│                      │                                   │
│                      ↓ ルーティング (/api/v1/* のみ)      │
│  ┌──────────────────────────────────────────────────┐  │
│  │ Bookinfo App (namespace: bookinfo)               │  │
│  │  - productpage (port 9080) ← Kong管理対象       │  │
│  │    └─ /api/v1/products                           │  │
│  │    └─ /api/v1/products/{id}                      │  │
│  │    └─ /api/v1/products/{id}/reviews              │  │
│  │    └─ /api/v1/products/{id}/ratings              │  │
│  │                                                    │  │
│  │  ※ reviews, ratings, details は内部で利用       │  │
│  └──────────────────────────────────────────────────┘  │
│                                                          │
│  ┌──────────────────────────────────────────────────┐  │
│  │ Monitoring (namespace: monitoring)                │  │
│  │  - Prometheus (メトリクス収集・保存)             │  │
│  │  - Grafana (可視化ダッシュボード)                │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### Kong 設定管理 (OpenAPI-Driven)

このプロジェクトは **OpenAPI 仕様を Single Source of Truth (SSoT)** として採用し、**productpage の `/api/v1/*` エンドポイントのみ**を管理:

```
kong/specs/openapi.yaml (SSoT)
  ↓ deck file openapi2kong
kong/configs/generated-kong.yaml (基本設定)
  ↓ deck file add-plugins
kong/configs/final-kong.yaml (プラグイン追加後)
  ↓ deck gateway sync
Konnect (自動デプロイ)
```

**管理対象エンドポイント:**

- `GET /products` - 商品一覧
- `GET /products/{id}` - 商品詳細
- `GET /products/{id}/reviews` - レビュー一覧
- `GET /products/{id}/ratings` - 評価情報

**管理対象外:**

- `/productpage` - HTML ページ
- その他 `/api/v1` 配下以外のエンドポイント

**利点:**

- ✅ API 仕様と Kong 設定の一元管理
- ✅ OpenAPI 変更で自動的に Kong 設定更新
- ✅ Dev Portal 自動同期
- ✅ 手動設定ファイル不要

## 前提条件

### 必須ツール

- Docker Engine (Docker Desktop / Colima / Podman)
- kubectl v1.34.1+
- Helm v3.18.4+
- kind v1.34.0+
- deck v1.49.2+ (Kong 設定管理)
- curl (動作確認用)

### Konnect 認証情報

以下のファイルを配置してください:

```bash
# Kong Cluster証明書
kong/secrets/tls.crt
kong/secrets/tls.key

# Konnect Personal Access Token
~/.konnect-token
```

## クイックスタート

```bash
# 全環境構築（約5分）
./scripts/setup.sh

# → 自動的にポートフォワードが開始されます:
#   - Kong Proxy:  http://localhost:8000
#   - Grafana:     http://localhost:3000 (admin/admin)
#   - Prometheus:  http://localhost:9090

# 動作確認（Bookinfo APIを呼び出し）
curl http://localhost:8000/products
curl http://localhost:8000/products/0
curl http://localhost:8000/products/0/reviews
curl http://localhost:8000/products/0/ratings

# テストリクエスト送信（75リクエスト）
./scripts/send-test-requests.sh

# Kong設定更新
deck file openapi2kong --spec kong/specs/openapi.yaml --output-file kong/configs/generated-kong.yaml
deck file add-plugins -s kong/configs/generated-kong.yaml kong/configs/service-plugins.yaml -o kong/configs/final-kong.yaml
deck gateway sync kong/configs/final-kong.yaml kong/configs/global-plugins.yaml --konnect-control-plane-name kong-work

# Kong 個別管理
./scripts/start-kong.sh            # Kong DP起動
./scripts/stop-kong.sh             # Kong DP停止
./scripts/redeploy-kong.sh         # Kong DP再デプロイ

# Bookinfo アプリケーション管理
./scripts/deploy-bookinfo.sh      # Bookinfo デプロイ
./scripts/cleanup-bookinfo.sh     # Bookinfo 削除

# モニタリング 個別管理
./scripts/setup-monitoring.sh      # モニタリング起動
./scripts/cleanup-monitoring.sh    # モニタリング削除

# 全環境削除
./scripts/cleanup.sh
```

**スクリプト実行フロー:**

```
setup.sh
  ↓
├─ 基盤構築 (Cluster, Helm, MetalLB)
├─ Kong namespace & 証明書作成
├─ setup-monitoring.sh
│   ├─ Namespace作成
│   ├─ kube-prometheus-stack インストール
│   ├─ ServiceMonitor作成
│   └─ ポートフォワード起動 (3000, 9090)
├─ start-kong.sh
│   ├─ Kong デプロイ
│   └─ ポートフォワード起動 (8000)
└─ deploy-bookinfo.sh
    └─ Bookinfo デプロイ (productpage, details, reviews, ratings)
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
│   ├── specs/                # OpenAPI仕様 (SSoT)
│   │   └── openapi.yaml      # ⭐ Bookinfo API仕様 (Kong設定の単一情報源)
│   └── configs/              # Kong設定ファイル
│       ├── generated-kong.yaml    # OpenAPIから生成された基本設定
│       ├── service-plugins.yaml   # サービスプラグイン定義 (rate-limiting)
│       ├── global-plugins.yaml    # グローバルプラグイン (prometheus, file-log)
│       └── final-kong.yaml        # 最終的なKong設定 (Konnectデプロイ用)
├── bookinfo/                 # Bookinfo アプリケーション
│   └── bookinfo-deployment.yaml  # Kubernetes Deployment/Service定義
├── monitoring/               # モニタリング設定
│   ├── prometheus-values.yaml    # Prometheus+Grafana設定
│   └── kong-servicemonitor.yaml  # KongメトリクスServiceMonitor
├── scripts/                  # 自動化スクリプト
│   ├── setup.sh              # ⭐ 全体セットアップ (クラスター+Kong+モニタリング+Bookinfo)
│   ├── cleanup.sh            # ⭐ 全体削除 (Bookinfo+モニタリング+Kong+クラスター)
│   ├── start-kong.sh         # Kong DP起動
│   ├── stop-kong.sh          # Kong DP停止
│   ├── redeploy-kong.sh      # Kong DP再デプロイ (stop→start)
│   ├── deploy-bookinfo.sh    # Bookinfo デプロイ
│   ├── cleanup-bookinfo.sh   # Bookinfo 削除
│   ├── setup-monitoring.sh   # モニタリングセットアップ
│   ├── cleanup-monitoring.sh # モニタリング削除
│   ├── send-test-requests.sh # テストトラフィック生成 (Grafana用)
│   └── export-konnect-config.sh  # Konnect設定エクスポート
├── .github/
│   └── workflows/
│       └── deploy-to-konnect.yml  # OpenAPI変更時の自動デプロイ
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
4. **Kong namespace & 証明書 Secret 作成**
5. **モニタリングスタックデプロイ** (`setup-monitoring.sh` を呼び出し)
6. **Kong DP デプロイ** (`start-kong.sh` を呼び出し)
7. **Bookinfo アプリケーションデプロイ** (`deploy-bookinfo.sh` を呼び出し)
8. **ポートフォワード自動開始** (Kong:8000, Grafana:3000, Prometheus:9090)

**所要時間:** 約 5 分

**デプロイされるもの:**

- ✅ Kubernetes クラスター (kind)
- ✅ LoadBalancer (MetalLB)
- ✅ Prometheus + Grafana + Alertmanager
- ✅ Node Exporter × 4
- ✅ Kong ServiceMonitor
- ✅ Kong Data Plane (HPA 有効、Prometheus プラグイン設定済み)
- ✅ Bookinfo マイクロサービス (productpage, details, reviews, ratings)
- ✅ ポートフォワード (バックグラウンドプロセス)

**自動的にアクセス可能:**

- http://localhost:8000 (Kong Proxy)
- http://localhost:8000/products (Bookinfo API)
- http://localhost:3000 (Grafana, admin/admin)
- http://localhost:9090 (Prometheus)

---

### `scripts/cleanup.sh` ⭐ メインスクリプト

**環境全体を削除します。**

**処理内容:**

1. **Bookinfo アプリケーション削除** (`cleanup-bookinfo.sh` を呼び出し)
2. **Kong DP 削除** (`stop-kong.sh` を呼び出し)
3. **モニタリングスタック削除** (`cleanup-monitoring.sh` を呼び出し)
4. Kong namespace 削除
5. MetalLB Helm リリース削除
6. metallb-system namespace 削除
7. kind クラスター削除

**所要時間:** 約 15 秒

---

### `scripts/deploy-bookinfo.sh`

**Bookinfo マイクロサービスをデプロイします。**

**処理内容:**

1. bookinfo namespace に Bookinfo Deployment/Service を作成
2. 4 つのサービス (productpage, details, reviews, ratings) をデプロイ
3. 各サービスはポート 9080 で公開

**使用場面:**

- 初回セットアップ後
- Bookinfo 削除後の再デプロイ

**所要時間:** 約 30 秒

---

### `scripts/cleanup-bookinfo.sh`

**Bookinfo マイクロサービスを削除します。**

**処理内容:**

1. Bookinfo Deployment と Service を削除
2. Pod 削除待機

**使用場面:**

- Bookinfo の再デプロイ前
- テスト環境のクリーンアップ

**所要時間:** 約 10 秒

---

### `scripts/start-kong.sh`

**Kong DP のみを起動します。**

**処理内容:**

1. kong namespace 存在確認（なければ作成）
2. 証明書 Secret 作成（必要な場合）
3. Kong イメージロード
4. Kong Helm デプロイ (HPA 有効、status endpoint 有効)
5. ポートフォワード起動 (8000)

**使用場面:**

- stop 後の再起動
- Kong DP のみを個別デプロイ

**所要時間:** 約 1 分

---

### `scripts/stop-kong.sh`

**Kong DP のみを停止します。**

**処理内容:**

1. Kong Proxy ポートフォワード停止
2. Kong Helm リリースアンインストール
3. Pod 削除待機

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
4. ポートフォワード起動 (Grafana:3000, Prometheus:9090)

**使用場面:**

- モニタリングのみを個別デプロイ
- モニタリングの再構築

**所要時間:** 約 2 分

**重要:** Kong namespace が存在する必要があります（ServiceMonitor を kong namespace に作成するため）

---

### `scripts/cleanup-monitoring.sh`

**モニタリングスタックを削除します。**

**処理内容:**

1. ポートフォワード停止 (Grafana, Prometheus)
2. Kong ServiceMonitor 削除
3. kube-prometheus-stack アンインストール
4. monitoring namespace 削除

**使用場面:**

- モニタリングのみを個別削除
- モニタリングの再構築前

**所要時間:** 約 10 秒

---

### `scripts/send-test-requests.sh`

**Bookinfo API にテストリクエストを送信し、Grafana 用のメトリクスを生成します。**

**処理内容:**

1. Kong Proxy 経由で 70 回のリクエストを送信
   - 55 回の成功リクエスト (200 OK)
   - 15 回のエラーリクエスト (404 Not Found)
2. 様々なエンドポイントをテスト (`/products`, `/details/0`, `/products/0/reviews`, etc.)

**使用場面:**

- Grafana ダッシュボードのテスト
- Kong メトリクスの動作確認
- デモ・プレゼンテーション用のトラフィック生成

**所要時間:** 約 5 秒

**使用例:**

```bash
# テストトラフィックを生成
./scripts/send-test-requests.sh

# Grafana で以下のクエリを実行してメトリクスを確認
# sum(rate(kong_http_requests_total[1m])) by (code)
```

---

### `scripts/export-konnect-config.sh`

**Konnect 上の Kong 設定をエクスポートします。**

**処理内容:**

1. `deck` CLI を使用して Konnect CP から設定を取得
2. `kong/configs/konnect-export.yaml` に保存

**使用場面:**

- Konnect 上の現在の設定を確認
- ローカル設定との差分確認
- バックアップ作成

**所要時間:** 約 3 秒

**使用例:**

```bash
# 環境変数を設定
export KONNECT_ADDR='https://b9b1351cc2.us.cp.konghq.com'
export KONNECT_TOKEN='your-konnect-token'

# エクスポート実行
./scripts/export-konnect-config.sh
```

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
# setup.sh または setup-monitoring.sh で自動起動されます
# http://localhost:3000
# ユーザー名: admin
# パスワード: admin

# 手動で起動する場合
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
```

**Prometheus:**

```bash
# setup.sh または setup-monitoring.sh で自動起動されます
# http://localhost:9090

# 手動で起動する場合
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
```

### Kong メトリクス

Grafana で利用可能な Kong メトリクス:

**基本メトリクス (常に利用可能):**

- `kong_dataplane_config_hash` - データプレーン設定ハッシュ
- `kong_memory_lua_shared_dict_bytes` - Lua 共有メモリ使用量
- `kong_memory_lua_shared_dict_total_bytes` - Lua 共有メモリ総量
- `kong_nginx_connections_total` - Nginx 接続数 (accepted/handled/reading/writing/waiting)
- `kong_nginx_requests_total` - Nginx 総リクエスト数

**HTTP メトリクス (Prometheus プラグイン設定済み):**

- `kong_http_requests_total` - HTTP リクエスト総数 (Service/Route/Code 別)
- `kong_bandwidth_bytes` - 帯域幅使用量 (type=egress/ingress, service, route)
- `kong_kong_latency_ms_*` - Kong 処理レイテンシ (bucket, count, sum)
- `kong_request_latency_ms_*` - 総リクエストレイテンシ (bucket, count, sum)
- `kong_upstream_latency_ms_*` - アップストリームレイテンシ (bucket, count, sum)

### Prometheus クエリ例

```promql
# リクエストレート (全体)
sum(rate(kong_http_requests_total[1m]))

# Service別のリクエストレート
sum(rate(kong_http_requests_total[1m])) by (exported_service)

# HTTPステータスコード別のリクエストレート
sum(rate(kong_http_requests_total[1m])) by (code)

# Route別のリクエストレート
sum(rate(kong_http_requests_total[1m])) by (route)

# エラーレート (4xx + 5xx)
sum(rate(kong_http_requests_total{code=~"[45].."}[1m]))

# 成功率 (%)
sum(rate(kong_http_requests_total{code=~"2.."}[1m])) / sum(rate(kong_http_requests_total[1m])) * 100

# レイテンシ (p50, p95, p99)
histogram_quantile(0.50, sum(rate(kong_request_latency_ms_bucket[1m])) by (le))
histogram_quantile(0.95, sum(rate(kong_request_latency_ms_bucket[1m])) by (le))
histogram_quantile(0.99, sum(rate(kong_request_latency_ms_bucket[1m])) by (le))

# 帯域幅 (送信)
sum(rate(kong_bandwidth_bytes{type="egress"}[1m]))

# 帯域幅 (受信)
sum(rate(kong_bandwidth_bytes{type="ingress"}[1m]))
```

### Grafana ダッシュボード

**推奨ダッシュボード:**

1. **Kong (official)** - Kong 公式ダッシュボード

   - Import ID: `7424`
   - Home → Dashboards → New → Import → 7424 を入力

2. **Kubernetes / Compute Resources / Cluster** - クラスタ全体のリソース

   - インストール済み

3. **Kubernetes / Compute Resources / Namespace (Pods)** - Pod 別リソース

   - インストール済み

4. **Node Exporter / Nodes** - ノード詳細メトリクス
   - インストール済み

### テストトラフィックの生成

メトリクスを視覚化するため、テストリクエストを送信できます:

```bash
# 70回のリクエストを送信 (55回成功、15回エラー)
./scripts/send-test-requests.sh

# Grafana でメトリクスを確認
# http://localhost:3000
# Explore → Prometheus → Metrics browser で以下を入力:
#   - kong_http_requests_total
#   - sum(rate(kong_http_requests_total[1m])) by (code)
```

### 重要な設定

**Kong Prometheus プラグイン (グローバル設定):**

`kong/configs/global-plugins.yaml` で設定済み:

```yaml
plugins:
  - name: prometheus
    config:
      bandwidth_metrics: true
      latency_metrics: true
      status_code_metrics: true
      upstream_health_metrics: true
      per_consumer: false
```

**Kong ServiceMonitor:**

`monitoring/kong-servicemonitor.yaml` で設定済み:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: kong-servicemonitor
  namespace: kong
  labels:
    release: kube-prometheus-stack # ← 重要: Prometheus Operatorが認識するラベル
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: kong
  endpoints:
    - port: status # Kong status endpoint (8100)
      path: /metrics
      interval: 30s
```

**Kong values.yaml 設定:**

```yaml
env:
  status_listen: "0.0.0.0:8100" # メトリクスエンドポイント有効化

status:
  enabled: true
  http:
    enabled: true
    containerPort: 8100

serviceMonitor:
  enabled: true
  labels:
    release: kube-prometheus-stack # Prometheus Operatorが認識するラベル
```

### トラブルシューティング

**メトリクスが表示されない:**

```bash
# 1. Kong Podが正常に動作しているか確認
kubectl get pods -n kong

# 2. ServiceMonitorが作成されているか確認
kubectl get servicemonitor -n kong

# 3. Prometheusターゲットの状態確認
# http://localhost:9090/targets で "my-kong-kong-metrics" を確認
# Status: UP であることを確認

# 4. Kong status endpointが応答するか確認
kubectl port-forward -n kong svc/my-kong-kong-status 8100:8100
curl http://localhost:8100/metrics
# → kong_* メトリクスが表示されるはず

# 5. Prometheusでクエリを実行
# http://localhost:9090/graph
# up{job="my-kong-kong-metrics"} → 1 であることを確認
```

**HTTP メトリクス (kong_http_requests_total) が表示されない:**

```bash
# Kong経由でリクエストを送信してメトリクスを生成
curl http://localhost:8000/products
curl http://localhost:8000/products/0
curl http://localhost:8000/details/0

# または一括送信
./scripts/send-test-requests.sh

# Prometheusで確認
# http://localhost:9090/graph
# kong_http_requests_total → データが表示されるはず
```

### 削除

```bash
./scripts/cleanup-monitoring.sh
```

---

## 管理コマンド

### Kong 設定の更新 (OpenAPI-driven)

**重要:** Kong 設定は `kong/specs/openapi.yaml` が単一情報源 (Single Source of Truth) です。

**設定更新フロー:**

```bash
# 1. OpenAPI仕様を編集
vim kong/specs/openapi.yaml

# 2. Kong設定ファイルを生成
cd kong/specs
deck file openapi2kong --spec openapi.yaml --output-file ../configs/bookinfo-kong-generated.yaml

# 3. 設定を検証
cd ../configs
deck file validate bookinfo-kong-generated.yaml global-plugins.yaml

# 4. Konnectにデプロイ (差分確認)
deck gateway diff bookinfo-kong-generated.yaml global-plugins.yaml \
  --konnect-addr https://b9b1351cc2.us.cp.konghq.com \
  --konnect-token $KONNECT_TOKEN

# 5. Konnectにデプロイ (適用)
deck gateway sync bookinfo-kong-generated.yaml global-plugins.yaml \
  --konnect-addr https://b9b1351cc2.us.cp.konghq.com \
  --konnect-token $KONNECT_TOKEN
```

**GitHub Actions による自動デプロイ:**

`kong/specs/openapi.yaml` を変更して main ブランチにプッシュすると、GitHub Actions が自動的に:

1. `deck file openapi2kong` で Kong 設定を生成
2. `deck gateway diff` で差分を確認
3. `deck gateway sync` で Konnect にデプロイ

**.github/workflows/deploy-to-konnect.yml** を参照

---

### 新しい API エンドポイントの追加

**例: `/products/{id}/ratings` エンドポイントを追加**

```yaml
# kong/specs/openapi.yaml

paths:
  /products/{id}/ratings:
    get:
      summary: Get product ratings
      operationId: getProductRatings
      tags:
        - ratings # ← 既存の ratings サービスタグを使用
      parameters:
        - name: id
          in: path
          required: true
          schema:
            type: integer
      responses:
        "200":
          description: Successful response
      # パスレベルの servers オーバーライド (重要!)
      servers:
        - url: http://ratings.bookinfo.svc.cluster.local:9080/api/v1

tags:
  - name: ratings
    x-kong-service-defaults:
      path: /api/v1 # ← OpenAPI仕様から自動削除され、Kong設定に反映
```

**設定ファイル生成とデプロイ:**

```bash
cd kong/specs
deck file openapi2kong --spec openapi.yaml --output-file ../configs/bookinfo-kong-generated.yaml
cd ../configs
deck gateway sync bookinfo-kong-generated.yaml global-plugins.yaml \
  --konnect-addr https://b9b1351cc2.us.cp.konghq.com \
  --konnect-token $KONNECT_TOKEN
```

**動作確認:**

```bash
curl http://localhost:8000/products/0/ratings
```

---

### グローバルプラグインの追加

**例: Rate Limiting プラグインを追加**

```yaml
# kong/configs/global-plugins.yaml

_format_version: "3.0"

plugins:
  - name: prometheus
    config:
      bandwidth_metrics: true
      latency_metrics: true
      status_code_metrics: true
      upstream_health_metrics: true
      per_consumer: false

  - name: rate-limiting # ← 新規追加
    config:
      minute: 100
      policy: local
```

**Konnect にデプロイ:**

```bash
cd kong/configs
deck gateway sync bookinfo-kong-generated.yaml global-plugins.yaml \
  --konnect-addr https://b9b1351cc2.us.cp.konghq.com \
  --konnect-token $KONNECT_TOKEN
```

**注意:** プラグインは `global-plugins.yaml` で管理し、`openapi.yaml` には含めません（関心の分離）

---

### Konnect 設定のエクスポート

現在の Konnect 設定をローカルにエクスポート:

```bash
./scripts/export-konnect-config.sh

# 出力: kong/configs/konnect-export.yaml
```

ローカル設定との差分確認:

```bash
cd kong/configs
diff bookinfo-kong-generated.yaml konnect-export.yaml
```

---

### ポートフォワード管理

各スクリプトが自身のポートフォワードを管理する設計になっています。

**自動起動:**

| スクリプト            | ポート | 対象サービス | ステップ |
| --------------------- | ------ | ------------ | -------- |
| `start-kong.sh`       | 8000   | Kong Proxy   | Step 4/4 |
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

# Bookinfo確認
kubectl get pods,svc -n bookinfo

# モニタリング確認
kubectl get pods,svc -n monitoring

# MetalLB確認
kubectl get pods -n metallb-system
kubectl get ipaddresspool,l2advertisement -n metallb-system

# ServiceMonitor確認 (Prometheus Operatorターゲット)
kubectl get servicemonitor -n kong
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

---

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
- ✅ Prometheus + Grafana + Alertmanager
- ✅ Kong Data Plane (Prometheus プラグイン設定済み)
- ✅ Bookinfo マイクロサービス
- ✅ 全ポートフォワード

---

### 個別の復元

```bash
# Kong DPのみ復元
./scripts/stop-kong.sh && ./scripts/start-kong.sh

# Bookinfoのみ復元
./scripts/cleanup-bookinfo.sh && ./scripts/deploy-bookinfo.sh

# モニタリングのみ復元
./scripts/cleanup-monitoring.sh && ./scripts/setup-monitoring.sh
```

---

### 手動復元（参考）

自動スクリプトを使わず、手動で復元する手順:

```bash
# 1. Bookinfo削除
kubectl delete -f bookinfo/bookinfo-deployment.yaml

# 2. モニタリング削除
kubectl delete -f monitoring/kong-servicemonitor.yaml
helm uninstall kube-prometheus-stack -n monitoring
kubectl delete namespace monitoring

# 3. Kong DP削除
helm uninstall my-kong -n kong
kubectl delete namespace kong

# 4. MetalLB削除
helm uninstall metallb -n metallb-system
kubectl delete namespace metallb-system

# 5. クラスター削除
kind delete cluster --name kong-k8s

# --- 再構築 ---

# 6. クラスター作成
kind create cluster --config infrastructure/kind-config.yaml

# 7. Helmリポジトリ追加
helm repo add kong https://charts.konghq.com
helm repo add metallb https://metallb.github.io/metallb
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# 8. MetalLBを復元
helm install metallb metallb/metallb -n metallb-system --create-namespace
kubectl wait --namespace metallb-system --for=condition=ready pod --selector=app.kubernetes.io/name=metallb --timeout=90s
kubectl apply -f infrastructure/metallb-config.yaml

# 9. Kong namespace と Secret を作成
kubectl create namespace kong
kubectl create secret tls kong-cluster-cert -n kong \
  --cert=kong/secrets/tls.crt \
  --key=kong/secrets/tls.key

# 10. モニタリングスタックをデプロイ
kubectl create namespace monitoring
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack -n monitoring --values monitoring/prometheus-values.yaml
kubectl wait --namespace monitoring --for=condition=ready pod --selector=app.kubernetes.io/name=grafana --timeout=300s
kubectl apply -f monitoring/kong-servicemonitor.yaml

# 11. Kongイメージロード
docker pull ghcr.io/ftuajii/bookinfo/kong-gateway:3.10
kind load docker-image ghcr.io/ftuajii/bookinfo/kong-gateway:3.10 --name kong-k8s

# 12. Kongをデプロイ
helm install my-kong kong/kong -n kong --skip-crds --values kong/values.yaml

# 13. Bookinfoをデプロイ
kubectl apply -f bookinfo/bookinfo-deployment.yaml
```

---

## トラブルシューティング

### Kong Pod が起動しない

```bash
# Pod状態確認
kubectl get pods -n kong
kubectl describe pod -n kong <pod-name>

# ログ確認
kubectl logs -n kong <pod-name>

# Probe設定確認 (デフォルトのProbeを使用)
kubectl get pod -n kong <pod-name> -o yaml | grep -A 10 Probe

# 証明書Secret確認
kubectl get secret kong-cluster-cert -n kong
kubectl describe secret kong-cluster-cert -n kong

# Konnect接続確認 (ログで確認)
kubectl logs -n kong <pod-name> | grep -i "control plane"
```

**よくある原因:**

- 証明書が正しく配置されていない → `kong/secrets/tls.crt` と `tls.key` を確認
- Konnect CP アドレスが間違っている → `kong/values.yaml` の `cluster_control_plane` を確認
- Probe のタイムアウト → デフォルト設定を使用 (カスタム Probe は削除済み)

---

### Bookinfo Pod が起動しない

```bash
# Pod状態確認
kubectl get pods -n bookinfo

# 詳細確認
kubectl describe pod -n bookinfo <pod-name>

# ログ確認
kubectl logs -n bookinfo <pod-name>

# イメージプル確認
kubectl get events -n bookinfo | grep -i pull
```

**よくある原因:**

- イメージがプルできない → `docker.io/istio/examples-bookinfo-*` が利用可能か確認
- リソース不足 → `kubectl top nodes` でノードリソースを確認

---

### API リクエストが 404 を返す

```bash
# 1. Kong Podが正常に動作しているか確認
kubectl get pods -n kong

# 2. Bookinfo Podが正常に動作しているか確認
kubectl get pods | grep -E 'productpage|details|reviews|ratings'

# 3. Kong経由でリクエストを送信
curl -v http://localhost:8000/products

# 4. Konnect設定を確認
./scripts/export-konnect-config.sh
cat kong/configs/konnect-export.yaml

# 5. ローカル設定との差分を確認
cd kong/configs
diff bookinfo-kong-generated.yaml konnect-export.yaml
```

**よくある原因:**

- Konnect に設定がデプロイされていない → GitHub Actions または deck CLI でデプロイ
- OpenAPI の `servers` 設定が間違っている → `/api/v1` は URL 内に含める (paths には含めない)
- Bookinfo Service が存在しない → `kubectl get svc | grep -E 'productpage|details|reviews|ratings'`

**正しいリクエスト例:**

```bash
# ✅ 正しい (200 OK)
curl http://localhost:8000/products        # → http://productpage:9080/api/v1/products
curl http://localhost:8000/products/0      # → http://productpage:9080/api/v1/products/0
curl http://localhost:8000/details/0       # → http://details:9080/details/0 (no /api/v1)

# ❌ 間違い (404 Not Found)
curl http://localhost:8000/api/v1/products # → /api/v1 を2重に含めてはいけない
```

---

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

**Metrics Server インストール (オプション):**

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# kind用にTLS検証を無効化
kubectl patch -n kube-system deployment metrics-server --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

# 確認
kubectl top nodes
kubectl top pods -n kong
```

---

### LoadBalancer IP が割り当てられない

```bash
# MetalLBの状態確認
kubectl get pods -n metallb-system
kubectl get ipaddresspool -n metallb-system
kubectl describe ipaddresspool -n metallb-system

# Service確認
kubectl get svc -n kong
kubectl describe svc my-kong-kong-proxy -n kong
```

**よくある原因:**

- MetalLB が正しく起動していない → `kubectl logs -n metallb-system <pod-name>`
- IP アドレスプールが設定されていない → `kubectl apply -f infrastructure/metallb-config.yaml`

---

### 外部アクセスできない

kind クラスターの MetalLB IP (`172.21.255.200`) はホストから直接アクセス不可。

**解決策:**

```bash
# port-forwardを使用 (推奨)
kubectl port-forward -n kong svc/my-kong-kong-proxy 8000:80
curl http://localhost:8000

# または setup.sh で自動起動
./scripts/setup.sh
# → 自動的に http://localhost:8000 でアクセス可能
```

---

### Prometheus が Kong メトリクスを収集しない

```bash
# 1. ServiceMonitorが作成されているか確認
kubectl get servicemonitor -n kong
kubectl describe servicemonitor kong-servicemonitor -n kong

# 2. ServiceMonitorのラベルが正しいか確認 (release: kube-prometheus-stack)
kubectl get servicemonitor kong-servicemonitor -n kong -o yaml | grep -A 5 labels

# 3. Prometheusターゲットの状態確認
# http://localhost:9090/targets で "my-kong-kong-metrics" を確認
# Status: UP であることを確認

# 4. Kong status endpointが応答するか確認
kubectl port-forward -n kong svc/my-kong-kong-status 8100:8100
curl http://localhost:8100/metrics
# → kong_* メトリクスが表示されるはず

# 5. Prometheusでクエリを実行
# http://localhost:9090/graph
# up{job="my-kong-kong-metrics"} → 1 であることを確認
```

**よくある原因:**

- ServiceMonitor が Kong より後にデプロイされた → モニタリングスタックを先にデプロイ (`setup.sh` は正しい順序)
- ServiceMonitor のラベルが間違っている → `release: kube-prometheus-stack` が必要
- Kong status endpoint が無効 → `kong/values.yaml` で `status_listen: "0.0.0.0:8100"` を確認

---

### Grafana にデータが表示されない

```bash
# 1. Prometheusがメトリクスを収集しているか確認
# http://localhost:9090/graph
# kong_http_requests_total または kong_nginx_requests_total を検索

# 2. Grafana データソース確認
# http://localhost:3000 → Configuration → Data Sources → Prometheus
# URL: http://kube-prometheus-stack-prometheus:9090 であることを確認

# 3. テストトラフィックを生成
./scripts/send-test-requests.sh

# 4. Grafana でクエリを実行
# Explore → Prometheus → Metrics browser
# sum(rate(kong_http_requests_total[1m])) by (code)
```

**よくある原因:**

- メトリクスがまだ生成されていない → テストリクエストを送信
- Prometheus データソースが設定されていない → Grafana で確認
- クエリが間違っている → 上記の例を参照

---

### GitHub Actions デプロイが失敗する

```bash
# 1. GitHub Secrets が設定されているか確認
# Settings → Secrets and variables → Actions
# - KONNECT_ADDR
# - KONNECT_TOKEN

# 2. deck CLI バージョン確認
deck version

# 3. ローカルで手動デプロイを試す
cd kong/specs
deck file openapi2kong --spec openapi.yaml --output-file ../configs/bookinfo-kong-generated.yaml
cd ../configs
deck gateway sync bookinfo-kong-generated.yaml global-plugins.yaml \
  --konnect-addr $KONNECT_ADDR \
  --konnect-token $KONNECT_TOKEN

# 4. GitHub Actions ログを確認
# Actions → 失敗したワークフロー → ログを確認
```

**よくある原因:**

- KONNECT_TOKEN が無効 → Konnect UI で新しいトークンを生成
- OpenAPI 仕様が無効 → `deck file validate` でローカル検証
- deck CLI バージョンが古い → 最新版にアップデート

---

## API Spec 公開 (Dev Portal) - オプション

Kong Konnect Dev Portal に API 仕様を公開する機能を提供しています。

### 前提条件

- Konnect アカウント
- Konnect API トークン
- API Product ID と Version ID

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

📚 **[API Spec 公開ガイド](docs/API_SPEC_PUBLISHING.md)**

---

## セキュリティスキャン - オプション

このプロジェクトでは、**Trivy**を使用したコンテナイメージの脆弱性スキャンを CI/CD パイプラインに統合しています。

### 自動スキャン対象

**Kong Gateway ゴールデンイメージ**

- イメージ: `ghcr.io/ftuajii/bookinfo/kong-gateway:3.10`
- CRITICAL/HIGH/MEDIUM 脆弱性を検出
- GitHub Security タブで詳細レポート確認可能

### スキャン実行タイミング

- ✅ コード変更時 (main ブランチへのプッシュ)
- ✅ プルリクエスト作成時
- ✅ 定期実行 (毎週月曜 9:00 JST)
- ✅ 手動実行 (Actions → "Container Security Scan")

### ローカルでのスキャン

```bash
# Trivyのインストール
brew install aquasecurity/trivy/trivy

# Kong Gatewayイメージのスキャン
trivy image ghcr.io/ftuajii/bookinfo/kong-gateway:3.10

# CRITICAL/HIGHのみ表示
trivy image --severity CRITICAL,HIGH ghcr.io/ftuajii/bookinfo/kong-gateway:3.10
```

### スキャン結果の確認

1. **GitHub Security タブ**: リポジトリの Security → Code scanning
2. **Actions サマリー**: ワークフロー実行結果に統計表示
3. **ローカルレポート**: HTML 形式の詳細レポート生成可能

### 詳細ドキュメント

📚 **[セキュリティスキャンガイド](docs/SECURITY_SCANNING.md)**

---

## ベストプラクティス

### Kong 設定管理

1. **OpenAPI を単一情報源 (SSoT) として使用**

   - `kong/specs/openapi.yaml` のみを編集
   - `bookinfo-kong-generated.yaml` は自動生成（手動編集禁止）

2. **関心の分離**

   - API 仕様: `openapi.yaml`
   - インフラストラクチャプラグイン: `global-plugins.yaml`

3. **バージョン管理**
   - OpenAPI 仕様は Git で管理
   - 変更履歴を追跡可能
   - GitHub Actions で自動デプロイ

### モニタリング

1. **デプロイ順序を守る**

   - Prometheus Operator → ServiceMonitor → Kong DP
   - `setup.sh` は正しい順序で実行

2. **メトリクス収集の確認**

   - `http://localhost:9090/targets` で Kong ターゲットが UP
   - テストトラフィックを生成してメトリクスを確認

3. **ダッシュボード作成**
   - Kong 公式ダッシュボード (ID: 7424) を使用
   - カスタムダッシュボードも作成可能

### セキュリティ

1. **証明書管理**

   - `kong/secrets/` は `.gitignore` で除外
   - 証明書は安全に保管

2. **トークン管理**

   - Konnect トークンは GitHub Secrets に保存
   - ローカル環境変数も使用可能 (`.env` ファイルは `.gitignore`)

3. **脆弱性スキャン**
   - 定期的に Trivy スキャンを実行
   - CRITICAL/HIGH の脆弱性は優先的に対応

### 運用

1. **スクリプトの活用**

   - `setup.sh` で一括セットアップ
   - `cleanup.sh` で完全削除
   - 個別スクリプトで部分的な操作

2. **ログ確認**

   - `kubectl logs` でトラブルシューティング
   - Prometheus/Grafana でメトリクス監視

3. **定期メンテナンス**
   - Kong Gateway のバージョンアップデート
   - Prometheus/Grafana のバージョンアップデート
   - 不要なリソースのクリーンアップ

---

## 参考リンク

- [Kong Gateway Documentation](https://docs.konghq.com/gateway/latest/)
- [Kong Konnect Documentation](https://docs.konghq.com/konnect/)
- [deck CLI Documentation](https://docs.konghq.com/deck/latest/)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [kind Documentation](https://kind.sigs.k8s.io/)
- [MetalLB Documentation](https://metallb.universe.tf/)
- [Bookinfo Application](https://istio.io/latest/docs/examples/bookinfo/)

---

## ライセンス

このプロジェクトは MIT ライセンスの下で公開されています。
