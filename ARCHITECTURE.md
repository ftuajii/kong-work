# システムアーキテクチャ

## 全体構成図

```mermaid
graph TB
    subgraph "Kong Konnect (SaaS)"
        CP[Control Plane<br/>ルート・サービス・プラグイン管理]
        Portal[Dev Portal<br/>API仕様公開]
    end

    subgraph "Kubernetes Cluster (Kind)"
        subgraph "Namespace: kong"
            DP[Kong Data Plane<br/>Deployment HPA 1-5<br/>Port: 8000 Proxy<br/>Port: 8100 Status]
            ProxySvc[Service<br/>Type: LoadBalancer<br/>IP: 172.21.255.200]
            StatusSvc[Service<br/>Type: ClusterIP<br/>Port: 8100]
            DP --> ProxySvc
            DP --> StatusSvc
        end

        subgraph "Namespace: bookinfo"
            Product[productpage<br/>Port: 9080<br/>/api/v1/*]
            Details[details<br/>Port: 9080<br/>/*]
            Reviews[reviews<br/>Port: 9080<br/>/api/v1/*]
            Ratings[ratings<br/>Port: 9080<br/>/api/v1/*]
        end

        subgraph "Namespace: monitoring"
            subgraph "kube-prometheus-stack"
                PromOp[Prometheus Operator<br/>ServiceMonitor監視]
                Prom[Prometheus<br/>StatefulSet<br/>Port: 9090<br/>メトリクス収集・保存]
                Grafana[Grafana<br/>Deployment<br/>Port: 3000<br/>ダッシュボード]
                Alert[Alertmanager<br/>StatefulSet]
                NodeExp[node-exporter<br/>DaemonSet]
            end
        end

        subgraph "Namespace: metallb-system"
            Controller[MetalLB Controller<br/>IP割り当て管理]
            Speaker[MetalLB Speaker<br/>DaemonSet<br/>ARP/NDP]
        end

        subgraph "Nodes"
            ControlPlane[control-plane]
            Worker1[worker]
            Worker2[worker2]
            Worker3[worker3]
        end
    end

    subgraph "External Access"
        Client[Developer<br/>localhost]
    end

    CP -.mTLS<br/>証明書認証.-> DP
    DP --> Product
    DP --> Details
    DP --> Reviews
    DP --> Ratings

    StatusSvc -.ServiceMonitor<br/>namespace: kong.-> PromOp
    PromOp --> Prom
    Prom --> Grafana

    Controller --> ProxySvc
    Speaker --> ProxySvc

    Client -.port-forward<br/>8000.-> ProxySvc
    Client -.port-forward<br/>3000.-> Grafana
    Client -.port-forward<br/>9090.-> Prom

    style CP fill:#e1f5ff
    style Portal fill:#e1f5ff
    style DP fill:#fff4e6
    style Prom fill:#e8f5e9
    style Grafana fill:#e8f5e9
    style Product fill:#fce4ec
    style Details fill:#fce4ec
    style Reviews fill:#fce4ec
    style Ratings fill:#fce4ec
```

## Kong 設定管理フロー (OpenAPI-Driven)

```mermaid
sequenceDiagram
    participant Dev as 開発者
    participant OpenAPI as kong/specs/openapi.yaml
    participant CI as GitHub Actions
    participant Generated as bookinfo-kong-generated.yaml
    participant Plugins as global-plugins.yaml
    participant Deck as deck CLI
    participant Konnect as Kong Konnect CP
    participant DP as Kong Data Plane

    Dev->>OpenAPI: 1. API仕様を編集
    Note over OpenAPI: Single Source of Truth<br/>paths, servers, x-kong-*

    CI->>OpenAPI: 2. deck file openapi2kong
    OpenAPI->>Generated: 自動生成<br/>services, routes, upstreams

    CI->>Generated: 3. マージ
    CI->>Plugins: 3. マージ
    Generated->>Deck: bookinfo-kong-generated.yaml
    Plugins->>Deck: global-plugins.yaml

    Deck->>Konnect: 4. deck gateway sync<br/>--konnect-token
    Note over Konnect: 設定を自動更新

    Konnect-->>DP: 5. mTLS経由で配信
    Note over DP: 即座にルーティング開始
```

## リクエストフロー

```mermaid
sequenceDiagram
    participant Client as クライアント
    participant PF as port-forward
    participant Kong as Kong DP
    participant Plugin as Prometheusプラグイン
    participant Product as productpage
    participant Det as details
    participant Rev as reviews
    participant Metrics as メトリクス

    Client->>PF: GET /products/0
    PF->>Kong: localhost:8000

    Kong->>Kong: ルートマッチング
    Kong->>Plugin: プラグイン実行
    Plugin->>Metrics: 記録開始

    Kong->>Product: /api/v1/products/0
    Product->>Det: 内部呼び出し
    Product->>Rev: 内部呼び出し
    Rev-->>Product: レスポンス
    Det-->>Product: レスポンス
    Product-->>Kong: JSON

    Kong->>Plugin: レスポンス処理
    Plugin->>Metrics: レイテンシ記録

    Kong->>PF: 200 OK
    PF->>Client: レスポンス
```

## モニタリングフロー

```mermaid
graph LR
    subgraph "Kong DP (namespace: kong)"
        PrometheusPlugin[Prometheusプラグイン<br/>グローバル有効]
        StatusEndpoint[Status Endpoint<br/>:8100/metrics]
        PrometheusPlugin --> StatusEndpoint
    end

    subgraph "Monitoring (namespace: monitoring)"
        SM[ServiceMonitor<br/>namespace: kong<br/>selector: app=kong<br/>interval: 30s]
        PromOp[Prometheus Operator]
        Prom[Prometheus<br/>時系列DB<br/>retention: 15日]
        Grafana[Grafana<br/>ダッシュボード]

        SM -.検出.-> PromOp
        PromOp -.scrape_config生成.-> Prom
        Prom --> Grafana
    end

    StatusEndpoint -.scrape 30s間隔.-> Prom

    style PrometheusPlugin fill:#fff4e6
    style StatusEndpoint fill:#fff4e6
    style SM fill:#e8f5e9
    style PromOp fill:#e8f5e9
    style Prom fill:#e8f5e9
    style Grafana fill:#e8f5e9
```

## デプロイ順序 (setup.sh)

```mermaid
graph TD
    Start([setup.sh 実行])

    Start --> Step1[Step 1: Kindクラスター作成<br/>control-plane + worker×3]
    Step1 --> Step2[Step 2: Helmリポジトリ追加<br/>kong, metallb, prometheus-community]
    Step2 --> Step3[Step 3: MetalLB デプロイ<br/>Controller + Speaker<br/>IPPool: 172.21.255.200-250]
    Step3 --> Step4[Step 4: Kong namespace & 証明書作成<br/>kong-cluster-cert Secret]

    Step4 --> Step5[Step 5: モニタリングスタック<br/>kube-prometheus-stack<br/>+ ServiceMonitor作成]

    Step5 --> Step6[Step 6: Kong DP デプロイ<br/>HPA + Proxy + Status]

    Step6 --> Step7[Step 7: Bookinfo デプロイ<br/>productpage, details,<br/>reviews, ratings]

    Step7 --> End([完了])

    style Step4 fill:#ffe0b2
    style Step5 fill:#c8e6c9
    style Step6 fill:#fff9c4

    Note1[重要: Kong namespace を先に作成]
    Note2[重要: Prometheus Operator を<br/>Kong より先にデプロイ]
    Note3[重要: ServiceMonitor が<br/>Kong を即座に認識]

    Step4 -.-> Note1
    Step5 -.-> Note2
    Step6 -.-> Note3
```

## ネットワーク構成

```mermaid
graph TB
    subgraph "External"
        Dev[開発者<br/>localhost]
    end

    subgraph "Kind Cluster Network"
        subgraph "Services"
            KongProxy[Kong Proxy Service<br/>Type: LoadBalancer<br/>172.21.255.200:8000]
            KongStatus[Kong Status Service<br/>Type: ClusterIP<br/>my-kong-kong-status:8100]
            GrafanaSvc[Grafana Service<br/>Type: ClusterIP<br/>kube-prometheus-stack-grafana:80]
            PromSvc[Prometheus Service<br/>Type: ClusterIP<br/>kube-prometheus-stack-prometheus:9090]
        end

        subgraph "Pods"
            KongPod[Kong DP Pod<br/>Proxy: 0.0.0.0:8000<br/>Status: 0.0.0.0:8100]
            ProductPod[productpage Pod<br/>0.0.0.0:9080]
            DetailsPod[details Pod<br/>0.0.0.0:9080]
            ReviewsPod[reviews Pod<br/>0.0.0.0:9080]
            RatingsPod[ratings Pod<br/>0.0.0.0:9080]
            PromPod[Prometheus Pod]
            GrafanaPod[Grafana Pod]
        end

        subgraph "MetalLB"
            IPPool[IPAddressPool<br/>172.21.255.200-250]
            L2Ad[L2Advertisement<br/>全ノードで応答]
        end
    end

    Dev -.kubectl port-forward<br/>:8000.-> KongProxy
    Dev -.kubectl port-forward<br/>:3000.-> GrafanaSvc
    Dev -.kubectl port-forward<br/>:9090.-> PromSvc

    KongProxy --> KongPod
    KongStatus --> KongPod
    GrafanaSvc --> GrafanaPod
    PromSvc --> PromPod

    KongPod --> ProductPod
    KongPod --> DetailsPod
    KongPod --> ReviewsPod
    KongPod --> RatingsPod

    IPPool --> KongProxy
    L2Ad --> KongProxy

    PromPod -.scrape :8100/metrics.-> KongStatus

    style KongProxy fill:#fff4e6
    style KongPod fill:#fff4e6
    style PromPod fill:#e8f5e9
    style GrafanaPod fill:#e8f5e9
```

## コンポーネント一覧

### Kong 関連

| コンポーネント | 種類             | Namespace | ポート                         | 用途            |
| -------------- | ---------------- | --------- | ------------------------------ | --------------- |
| Kong DP        | Deployment (HPA) | kong      | 8000 (Proxy)<br/>8100 (Status) | API Gateway     |
| Proxy Service  | LoadBalancer     | kong      | 8000                           | 外部アクセス    |
| Status Service | ClusterIP        | kong      | 8100                           | メトリクス公開  |
| ServiceMonitor | Custom Resource  | kong      | -                              | Prometheus 連携 |

### Bookinfo 関連

| コンポーネント | 種類                 | Namespace | ポート | 用途           |
| -------------- | -------------------- | --------- | ------ | -------------- |
| productpage    | Deployment + Service | bookinfo  | 9080   | フロントエンド |
| details        | Deployment + Service | bookinfo  | 9080   | 書籍詳細       |
| reviews        | Deployment + Service | bookinfo  | 9080   | レビュー       |
| ratings        | Deployment + Service | bookinfo  | 9080   | 評価           |

### モニタリング関連

| コンポーネント      | 種類        | Namespace  | ポート | 用途                 |
| ------------------- | ----------- | ---------- | ------ | -------------------- |
| Prometheus          | StatefulSet | monitoring | 9090   | メトリクス収集・保存 |
| Grafana             | Deployment  | monitoring | 3000   | ダッシュボード       |
| Prometheus Operator | Deployment  | monitoring | -      | ServiceMonitor 監視  |
| Alertmanager        | StatefulSet | monitoring | 9093   | アラート管理         |
| node-exporter       | DaemonSet   | monitoring | 9100   | ノードメトリクス     |

### インフラ関連

| コンポーネント     | 種類       | Namespace      | ポート | 用途         |
| ------------------ | ---------- | -------------- | ------ | ------------ |
| MetalLB Controller | Deployment | metallb-system | -      | IP 割り当て  |
| MetalLB Speaker    | DaemonSet  | metallb-system | -      | ARP/NDP 応答 |

## メトリクス例

Kong Prometheus プラグインが収集するメトリクス:

```promql
# リクエスト総数
kong_http_requests_total{service="bookinfo-productpage", code="200"}

# レイテンシ（ヒストグラム）
kong_latency_bucket{type="request", service="bookinfo-productpage", le="100"}

# 帯域幅
kong_bandwidth_bytes{type="egress", service="bookinfo-productpage"}

# アップストリーム健全性
kong_upstream_target_health{upstream="bookinfo-productpage", target="productpage.bookinfo.svc.cluster.local:9080"}
```

Grafana で可視化可能なクエリ:

```promql
# リクエストレート（1分間の平均RPS）
sum(rate(kong_http_requests_total[1m])) by (service)

# エラーレート
sum(rate(kong_http_requests_total{code=~"5.."}[1m])) / sum(rate(kong_http_requests_total[1m]))

# P95レイテンシ
histogram_quantile(0.95, sum(rate(kong_latency_bucket[1m])) by (le))

# サービス別リクエスト数
sum(kong_http_requests_total) by (service)
```

## 参考リンク

- [Kong Gateway Documentation](https://docs.konghq.com/gateway/latest/)
- [Kong Konnect](https://docs.konghq.com/konnect/)
- [Bookinfo Application](https://istio.io/latest/docs/examples/bookinfo/)
- [Prometheus Operator](https://prometheus-operator.dev/)
- [Grafana Dashboards](https://grafana.com/grafana/dashboards/)
- [MetalLB](https://metallb.universe.tf/)
- [Kind](https://kind.sigs.k8s.io/)
