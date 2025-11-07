# Kong Konnect データプレーン on Kind

## 概要

- **クラスター名**: `kong-k8s`
- **ノード構成**: 1 control-plane + 2 worker nodes
- **LoadBalancer**: MetalLB (IP プール: 172.21.255.200-250)
- **Kong データプレーン**: Konnect CP 接続用に構成済み
- **Kong イメージ**: `ghcr.io/ftuajii/bookinfo/kong-gateway:3.10` (ゴールデンイメージ)
- **オートスケーリング**: HPA 有効 (1-5 Pods, CPU 70%でスケール)

## 前提条件

- ✅ Docker Engine 起動済み（Docker Desktop、Colima、Podman など）
- ✅ kubectl (v1.34.1+)
- ✅ Helm 3 (v3.18.4+)
- ✅ kind (v1.34.0+)
- ✅ curl (動作確認用)
- ✅ Konnect 証明書 (`kong/secrets/tls.crt`, `tls.key`)

## クイックスタート

```bash
# 環境構築（約4分）
./scripts/setup.sh

# 動作確認
kubectl port-forward -n kong svc/my-kong-kong-proxy 8000:80 &
curl http://localhost:8000

# Kong DP管理
./scripts/stop-kong.sh      # 停止
./scripts/start-kong.sh     # 起動
./scripts/redeploy-kong.sh  # 再デプロイ

# 環境削除
./scripts/cleanup.sh
```

## アーキテクチャ

### Kubernetes 構成

```
Cluster: kong-k8s
  ├─ Node: control-plane (管理ノード)
  │   └─ Kubernetes管理コンポーネント
  ├─ Node: worker (ワーカー1)
  │   └─ Kong DP Pods (HPA: 1-5個)
  └─ Node: worker2 (ワーカー2)
      └─ Kong DP Pods (分散配置)

MetalLB: LoadBalancer実装
  ├─ Controller (IPアドレス割り当て)
  └─ Speaker × 3 (各ノードでL2アナウンス)
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
├── scripts/                  # 自動化スクリプト
│   ├── setup.sh              # 環境全体セットアップ (kind+MetalLB+Kong)
│   ├── cleanup.sh            # 環境全体削除
│   ├── start-kong.sh         # Kong起動
│   ├── stop-kong.sh          # Kong停止
│   └── redeploy-kong.sh      # Kong再デプロイ (stop→start)
├── .gitignore
└── README.md
```

## スクリプト説明

### `scripts/setup.sh`

環境全体を自動構築します。

**処理内容:**

1. kind クラスター作成 (3 ノード)
2. Helm リポジトリ追加
3. MetalLB インストール & 設定
4. Kong namespace & 証明書 Secret 作成
5. Kong イメージロード
6. Kong Helm デプロイ (HPA 有効)

**所要時間:** 約 4 分

### `scripts/cleanup.sh`

環境全体を削除します。

**処理内容:**

1. Kong Helm リリース削除
2. MetalLB Helm リリース削除
3. namespace 削除
4. kind クラスター削除

**所要時間:** 約 10 秒

### `scripts/start-kong.sh`

Kong DP のみを起動します。

**処理内容:**

1. Kong イメージロード
2. Kong Helm デプロイ

**使用場面:** stop 後の再起動、初回デプロイ後

**所要時間:** 約 1 分

### `scripts/stop-kong.sh`

Kong DP のみを停止します。

**処理内容:**

1. Kong Helm リリースアンインストール

**使用場面:** 一時停止、メンテナンス前

**所要時間:** 約 10 秒

### `scripts/redeploy-kong.sh`

Kong DP を再デプロイします (stop→start)。

**使用場面:**

- `kong/values.yaml`変更後
- 設定初期化
- トラブルシューティング

**所要時間:** 約 1-2 分

## 管理コマンド

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

### 自動復元（推奨）

```bash
# 削除と再構築を一括実行
./scripts/cleanup.sh && ./scripts/setup.sh
```

### 手動復元

すべてのリソースを削除してから完全に復元する手順:

```bash
# 1. リソースを削除
helm uninstall my-kong -n kong
helm uninstall metallb -n metallb-system
kubectl delete namespace kong metallb-system

# 2. Helmリポジトリ追加（初回のみ）
helm repo add kong https://charts.konghq.com
helm repo add metallb https://metallb.github.io/metallb
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
