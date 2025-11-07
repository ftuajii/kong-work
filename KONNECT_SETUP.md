# Kong Konnect データプレーン セットアップ手順

## 前提条件

- ✅ Kong Konnect のアカウント
- ✅ コントロールプレーン作成済み
- ✅ kind クラスター稼働中 (`kind-kong-k8s`)
- ✅ MetalLB 導入済み

## セットアップ手順

### 1. Konnect CP から証明書と接続情報を取得

1. Kong Konnect にログイン: https://cloud.konghq.com/
2. Runtime Manager > 該当のコントロールプレーン > New Data Plane Node を選択
3. 以下の情報を取得:
   - クラスター証明書 (`cluster.crt`)
   - クラスター証明書キー (`cluster.key`)
   - Control Plane エンドポイント (例: `xxxxx.us.cp0.konghq.com:443`)
   - Telemetry エンドポイント (例: `xxxxx.us.tp0.konghq.com:443`)

### 2. 証明書を Secret に設定

証明書ファイルを base64 エンコード:

```bash
# 証明書をbase64エンコード
cat cluster.crt | base64

# 秘密鍵をbase64エンコード
cat cluster.key | base64
```

`kong-dp-deployment.yaml` の Secret セクションに設定:

```yaml
data:
  tls.crt: "<cluster.crtのbase64エンコード値>"
  tls.key: "<cluster.keyのbase64エンコード値>"
```

### 3. 接続エンドポイントを設定

`kong-dp-deployment.yaml` の Deployment の環境変数を更新:

```yaml
- name: KONG_CLUSTER_CONTROL_PLANE
  value: "xxxxx.us.cp0.konghq.com:443" # 実際のCPエンドポイント
- name: KONG_CLUSTER_SERVER_NAME
  value: "xxxxx.us.cp0.konghq.com" # CPのホスト名
- name: KONG_CLUSTER_TELEMETRY_ENDPOINT
  value: "xxxxx.us.tp0.konghq.com:443" # Telemetryエンドポイント
- name: KONG_CLUSTER_TELEMETRY_SERVER_NAME
  value: "xxxxx.us.tp0.konghq.com" # Telemetryのホスト名
```

### 4. データプレーンを再デプロイ

```bash
# 設定を反映
kubectl apply -f kong-dp-deployment.yaml

# ポッドの再起動を待つ
kubectl rollout status deployment/kong-dp -n kong

# 状態確認
kubectl get pods -n kong
kubectl get svc -n kong
```

### 5. 接続確認

**Konnect UI で確認:**

- Runtime Manager > 該当のコントロールプレーン
- Data Plane Nodes タブで新しいノードが表示され、ステータスが "Connected" になることを確認

**ログで確認:**

```bash
kubectl logs -n kong -l app=kong-dp --tail=50
```

### 6. 動作テスト

Konnect CP で Route と Service を設定後、以下でテスト:

```bash
# LoadBalancer経由
curl http://172.21.255.200/<your-route-path>

# NodePort経由
curl http://localhost:30000/<your-route-path>
```

## アクセス情報

### LoadBalancer 経由

- **HTTP**: `http://172.21.255.200:80`
- **HTTPS**: `https://172.21.255.200:443`

### NodePort 経由

- **HTTP**: `http://localhost:30000`
- **HTTPS**: `https://localhost:30443`

### その他

- **Status API**: Pod 内部ポート 8100

## トラブルシューティング

### ポッドが起動しない場合

```bash
kubectl describe pod -n kong -l app=kong-dp
kubectl logs -n kong -l app=kong-dp
```

### 証明書エラーの場合

- Secret の証明書が正しく base64 エンコードされているか確認
- 証明書の有効期限を確認
- Konnect CP から最新の証明書を再取得

### 接続できない場合

- エンドポイントの URL とポートが正しいか確認
- ネットワークから Konnect のエンドポイントに到達可能か確認
- ファイアウォール設定を確認
