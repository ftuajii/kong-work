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
            Product[productpage<br/>Port: 9080<br/>/api/v1/* ← Kong管理対象]
            Details[details<br/>Port: 9080<br/>内部利用のみ]
            Reviews[reviews<br/>Port: 9080<br/>内部利用のみ]
            Ratings[ratings<br/>Port: 9080<br/>内部利用のみ]

            Product -.内部呼び出し.-> Reviews
            Product -.内部呼び出し.-> Ratings
            Product -.内部呼び出し.-> Details
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
    DP -->|/api/v1/* のみ| Product

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
    style Details fill:#f5f5f5
    style Reviews fill:#f5f5f5
    style Ratings fill:#f5f5f5
```

## Kong 設定管理フロー (OpenAPI-Driven)

```mermaid
sequenceDiagram
    participant Dev as 開発者
    participant GitHub as GitHub
    participant Actions as GitHub Actions
    participant Security as Security Scan
    participant OpenAPI as kong/specs/openapi.yaml
    participant Deck as deck CLI
    participant ServicePlugins as service-plugins.yaml
    participant Generated as generated-kong.yaml
    participant Final as final-kong.yaml
    participant Konnect as Kong Konnect CP
    participant Portal as Dev Portal
    participant DP as Kong Data Plane

    Dev->>OpenAPI: 1. API仕様を編集
    Note over OpenAPI: Single Source of Truth<br/>productpage /api/v1/* のみ

    Dev->>GitHub: 2. Push to main
    GitHub->>Actions: トリガー

    Actions->>Security: 3. セキュリティスキャン
    Note over Security: Kong Gateway<br/>イメージの脆弱性チェック
    Security-->>Actions: ✅ スキャン成功

    Actions->>Portal: 4. API Spec公開
    Portal->>OpenAPI: openapi.yaml読み込み
    Note over Portal: Dev Portalに公開

    Actions->>Deck: 5. deck file openapi2kong
    Deck->>OpenAPI: openapi.yaml読み込み
    OpenAPI->>Generated: 自動生成<br/>service + routes

    Actions->>Deck: 6. deck file add-plugins
    Deck->>ServicePlugins: service-plugins.yaml読み込み
    Deck->>Generated: プラグイン追加
    Generated->>Final: 最終設定ファイル

    Actions->>Deck: 7. deck gateway sync
    Deck->>Konnect: final-kong.yaml<br/>+ global-plugins.yaml
    Note over Konnect: 設定を自動更新

    Konnect-->>DP: 8. mTLS経由で配信
    Note over DP: 即座にルーティング開始
```

## リクエストフロー

```mermaid
sequenceDiagram
    participant Client as クライアント
    participant PF as port-forward
    participant Kong as Kong DP
    participant Product as productpage
    participant Rev as reviews
    participant Rat as ratings
    participant Det as details
    participant Metrics as メトリクス

    Client->>PF: GET /products/0/reviews
    PF->>Kong: localhost:8000

    Kong->>Kong: ルートマッチング<br/>/products/{id}/reviews
    Kong->>Metrics: 記録開始

    Kong->>Product: /api/v1/products/0/reviews
    Note over Product: productpage内部で<br/>reviews を呼び出し
    Product->>Rev: /reviews/0
    Rev-->>Product: レビューJSON
    Note over Product: ratingsも必要なら<br/>内部で呼び出し
    Product->>Rat: /ratings/0
    Rat-->>Product: 評価JSON
    Product-->>Kong: 統合されたJSON

    Kong->>Metrics: レイテンシ記録

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

## CI/CD パイプライン

```mermaid
graph TB
    subgraph "トリガー"
        Push[OpenAPI変更<br/>Push to main]
        Schedule[定期実行<br/>毎週月曜 9:00 JST]
        Manual[手動実行<br/>workflow_dispatch]
    end

    subgraph "GitHub Actions"
        subgraph "security-scan.yml"
            Scan[コンテナスキャン<br/>Trivy]
            ScanCheck{脆弱性<br/>チェック}
            ScanResult[GitHub Security<br/>SARIF Upload]
        end

        subgraph "publish-api-spec.yml"
            Validate[OpenAPI検証]
            Publish[Dev Portal公開]
        end

        subgraph "deploy-to-konnect.yml"
            OpenAPI2Kong[deck file<br/>openapi2kong]
            AddPlugins[deck file<br/>add-plugins]
            Diff[deck gateway<br/>diff]
            Sync[deck gateway<br/>sync]
        end
    end

    subgraph "成果物"
        DevPortal[Dev Portal<br/>API仕様公開]
        KonnectCP[Konnect CP<br/>サービス・ルート<br/>プラグイン]
        SecurityTab[GitHub Security<br/>脆弱性レポート]
    end

    Push --> Scan
    Schedule --> Scan
    Manual --> Scan

    Scan --> ScanCheck
    ScanCheck -->|✅ 成功| Validate
    ScanCheck -->|❌ 失敗| ScanResult
    ScanCheck --> ScanResult

    Validate --> Publish
    Publish --> DevPortal

    ScanCheck -->|✅ 成功| OpenAPI2Kong
    OpenAPI2Kong --> AddPlugins
    AddPlugins --> Diff
    Diff --> Sync
    Sync --> KonnectCP

    style Scan fill:#ffe0b2
    style ScanCheck fill:#ffe0b2
    style Validate fill:#e1f5ff
    style Publish fill:#e1f5ff
    style OpenAPI2Kong fill:#fff4e6
    style AddPlugins fill:#fff4e6
    style Sync fill:#fff4e6
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

    Step7 --> End([完了<br/>Kong は productpage の<br/>/api/v1/* のみを管理])

    style Step4 fill:#ffe0b2
    style Step5 fill:#c8e6c9
    style Step6 fill:#fff9c4

    Note1[重要: Kong namespace を先に作成]
    Note2[重要: Prometheus Operator を<br/>Kong より先にデプロイ]
    Note3[重要: ServiceMonitor が<br/>Kong を即座に認識]
    Note4[注意: reviews/ratings/details は<br/>Kong管理対象外]

    Step4 -.-> Note1
    Step5 -.-> Note2
    Step6 -.-> Note3
    Step7 -.-> Note4
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
            ProductPod[productpage Pod<br/>0.0.0.0:9080<br/>/api/v1/* ← Kong管理]
            DetailsPod[details Pod<br/>0.0.0.0:9080<br/>内部利用のみ]
            ReviewsPod[reviews Pod<br/>0.0.0.0:9080<br/>内部利用のみ]
            RatingsPod[ratings Pod<br/>0.0.0.0:9080<br/>内部利用のみ]
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

    KongPod -->|/api/v1/* のみ| ProductPod
    ProductPod -.内部呼び出し.-> ReviewsPod
    ProductPod -.内部呼び出し.-> RatingsPod
    ProductPod -.内部呼び出し.-> DetailsPod

    IPPool --> KongProxy
    L2Ad --> KongProxy

    PromPod -.scrape :8100/metrics.-> KongStatus

    style KongProxy fill:#fff4e6
    style KongPod fill:#fff4e6
    style ProductPod fill:#fce4ec
    style DetailsPod fill:#f5f5f5
    style ReviewsPod fill:#f5f5f5
    style RatingsPod fill:#f5f5f5
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

| コンポーネント | 種類                 | Namespace | ポート | 用途                     | Kong 管理 |
| -------------- | -------------------- | --------- | ------ | ------------------------ | --------- |
| productpage    | Deployment + Service | bookinfo  | 9080   | API 統合サービス         | ✅        |
| details        | Deployment + Service | bookinfo  | 9080   | 書籍詳細（内部利用のみ） | ❌        |
| reviews        | Deployment + Service | bookinfo  | 9080   | レビュー（内部利用のみ） | ❌        |
| ratings        | Deployment + Service | bookinfo  | 9080   | 評価（内部利用のみ）     | ❌        |

**注意:** Kong は `productpage` の `/api/v1/*` エンドポイントのみを管理します。

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

Kong が収集するメトリクス（ServiceMonitor 経由で Prometheus に送信）:

```promql
# リクエスト総数（単一サービス bookinfo-api）
kong_http_requests_total{service="bookinfo-api", code="200"}

# レイテンシ（ヒストグラム）
kong_latency_bucket{type="request", service="bookinfo-api", le="100"}

# 帯域幅
kong_bandwidth_bytes{type="egress", service="bookinfo-api"}
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
