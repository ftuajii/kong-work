# Kong Konnect データプレーン on Kind

## 概要

- **クラスター名**: `kong-k8s`
- **ノード構成**: 1 control-plane + 2 worker nodes
- **LoadBalancer**: MetalLB (172.21.255.200-172.21.255.250)
- **Kong データプレーン**: Konnect CP 接続用に構成済み
- **Kong イメージ**: `ghcr.io/ftuajii/bookinfo/kong-gateway:3.10`

## セットアップ手順

### 1. kind クラスターの作成

```bash
kind create cluster --name kong-k8s --config kind-config.yaml
```

### 2. MetalLB（LoadBalancer）のセットアップ

```bash
# MetalLBをインストール
kubectl apply -f metallb-install.yaml

# MetalLBが起動するまで待機
kubectl wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb --timeout=90s

# IPアドレスプール設定を適用
kubectl apply -f metallb-config.yaml
```

### 3. Kong データプレーンのデプロイ

```bash
# Kongイメージをプル
docker pull ghcr.io/ftuajii/bookinfo/kong-gateway:3.10

# イメージをkindクラスターにロード
kind load docker-image ghcr.io/ftuajii/bookinfo/kong-gateway:3.10 --name kong-k8s

# データプレーンをデプロイ
kubectl apply -f kong-dp-deployment.yaml
```

### 4. Konnect CP 接続（オプション）

詳細は `KONNECT_SETUP.md` を参照してください。

## Kong Proxy アクセス情報

### LoadBalancer 経由

- **HTTP**: `http://172.21.255.200:80`
- **HTTPS**: `https://172.21.255.200:443`

### NodePort 経由（引き続き利用可能）

- **HTTP**: `http://localhost:30000`
- **HTTPS**: `http://localhost:30443`

### その他

- **Status API**: Pod 内部ポート 8100

## 管理コマンド

### クラスター管理

```bash
# クラスター一覧
kind get clusters

# クラスター削除
kind delete cluster --name kong-k8s

# コンテキスト確認
kubectl config current-context
kubectl config get-contexts
```

### Kong 管理

```bash
# ポッド確認
kubectl get pods -n kong

# サービス確認（LoadBalancer IPを確認）
kubectl get svc -n kong

# ログ確認
kubectl logs -n kong -l app=kong-dp

# すべてのリソース確認
kubectl get all -n kong
```

### MetalLB 管理

````bash
### MetalLB管理
```bash
# MetalLBの状態確認
kubectl get pods -n metallb-system

# IPアドレスプール確認
kubectl get ipaddresspool -n metallb-system

# L2Advertisement確認
kubectl get l2advertisement -n metallb-system
````

## 環境の完全復元

すべてのリソースを削除してから完全に復元する手順:

```bash
# 1. リソースを削除
kubectl delete namespace kong metallb-system

# 2. MetalLBを復元
kubectl apply -f metallb-install.yaml
kubectl wait --namespace metallb-system --for=condition=ready pod --selector=app=metallb --timeout=90s
kubectl apply -f metallb-config.yaml

# 3. Kongを復元
kubectl apply -f kong-dp-deployment.yaml
```

## ファイル構成

```
.
├── kind-config.yaml          # kindクラスター設定
├── metallb-install.yaml      # MetalLBインストールマニフェスト
├── metallb-config.yaml       # MetalLB IPアドレスプール設定
├── kong-dp-deployment.yaml   # Kongデータプレーンマニフェスト
├── KONNECT_SETUP.md          # Konnect CP接続手順
└── README.md                 # このファイル
```

## 前提条件

- ✅ Docker Desktop 起動済み
- ✅ kubectl (v1.34.1+)
- ✅ Helm 3 (v3.18.4+)
- ✅ kind インストール済み

```

## ファイル構成

```

.
├── kind-config.yaml # kind クラスター設定
├── metallb-config.yaml # MetalLB IP アドレスプール設定
├── kong-dp-deployment.yaml # Kong データプレーンマニフェスト
├── KONNECT_SETUP.md # Konnect CP 接続手順
└── README.md # このファイル

```

## 前提条件

- ✅ Docker Desktop 起動済み
- ✅ kubectl (v1.34.1+)
- ✅ Helm 3 (v3.18.4+)
- ✅ kind インストール済み
  kubectl config get-contexts

# クラスター情報

kubectl cluster-info

```

```

```
