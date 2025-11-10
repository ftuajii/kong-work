# Kong 宣言的設定ファイル

このディレクトリは Kong Gateway の宣言的設定ファイルを管理します。

## 📁 ファイル構成

```
kong/configs/
├── generated-kong.yaml      # ← deck file openapi2kong で自動生成
├── service-plugins.yaml     # サービスプラグイン定義 (deck file add-plugins用)
├── final-kong.yaml         # プラグイン追加後の最終設定 (Konnectデプロイ用)
├── global-plugins.yaml      # グローバルプラグイン (Prometheus など)
└── README.md                # このファイル
```

## 🎯 設計思想: OpenAPI-driven Kong 設定管理

**Single Source of Truth (SSoT): `kong/specs/openapi.yaml`**

Kong の設定は手動で作成せず、OpenAPI 仕様から自動生成します。

### アーキテクチャ

```
kong/specs/openapi.yaml (SSoT)
         ↓
  deck file openapi2kong
         ↓
kong/configs/generated-kong.yaml (基本設定)
         ↓
  deck file add-plugins
         ↓
kong/configs/final-kong.yaml (プラグイン追加後)
         +
kong/configs/global-plugins.yaml (手動管理)
         ↓
  deck gateway sync
         ↓
    Konnect Control Plane
         ↓
    Kong Data Plane
```

### ファイルの役割

| ファイル名             | 役割                       | 編集方法               |
| ---------------------- | -------------------------- | ---------------------- |
| `openapi.yaml`         | API 仕様の定義 (SSoT)      | ✅ 手動編集            |
| `generated-kong.yaml`  | Services/Routes の基本定義 | ❌ 自動生成 (編集禁止) |
| `service-plugins.yaml` | サービスプラグイン定義     | ✅ 手動編集            |
| `final-kong.yaml`      | プラグイン追加後の最終設定 | ❌ 自動生成 (編集禁止) |
| `global-plugins.yaml`  | グローバルプラグイン       | ✅ 手動編集            |

## 🔄 ワークフロー

### 1. API エンドポイントの追加・変更

**Step 1: OpenAPI 仕様を編集**

```bash
vim kong/specs/openapi.yaml
```

**例: 新しいエンドポイント `/products/{id}/ratings` を追加**

```yaml
paths:
  /products/{id}/ratings:
    get:
      summary: Get product ratings
      operationId: getProductRatings
      tags:
        - ratings # ← サービスタグ
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
```

**設定ファイル生成とデプロイ:**

```bash
cd kong/specs
deck file openapi2kong \
  --spec openapi.yaml \
  --output-file ../configs/bookinfo-kong-generated.yaml
```

**Step 3: 設定を検証**

```bash
cd kong/configs
deck file validate bookinfo-kong-generated.yaml global-plugins.yaml
```

**Step 4: Konnect にデプロイ (差分確認)**

```bash
deck gateway diff bookinfo-kong-generated.yaml global-plugins.yaml \
  --konnect-addr https://b9b1351cc2.us.cp.konghq.com \
  --konnect-token $KONNECT_TOKEN
```

**Step 5: Konnect にデプロイ (適用)**

```bash
deck gateway sync bookinfo-kong-generated.yaml global-plugins.yaml \
  --konnect-addr https://b9b1351cc2.us.cp.konghq.com \
  --konnect-token $KONNECT_TOKEN
```

---

### 2. グローバルプラグインの追加・変更

**Step 1: `global-plugins.yaml` を編集**

```bash
vim kong/configs/global-plugins.yaml
```

**例: Rate Limiting プラグインを追加**

```yaml
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

**Step 2: Konnect にデプロイ**

```bash
cd kong/configs
deck gateway sync bookinfo-kong-generated.yaml global-plugins.yaml \
  --konnect-addr https://b9b1351cc2.us.cp.konghq.com \
  --konnect-token $KONNECT_TOKEN
```

---

### 3. Konnect 設定のエクスポート (参考用)

現在の Konnect 設定を確認したい場合:

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

## 🚀 GitHub Actions による自動デプロイ

### セットアップ

1. **GitHub Secrets を設定** (リポジトリの Settings → Secrets and variables → Actions):

   - `KONNECT_ADDR`: Konnect Control Plane アドレス
   - `KONNECT_TOKEN`: Personal Access Token

2. **ワークフロー**: `.github/workflows/deploy-to-konnect.yml`

### 動作

`kong/specs/openapi.yaml` が main ブランチに push されると:

1. `deck file openapi2kong` で Kong 設定を自動生成
2. `deck gateway diff` で差分を確認
3. `deck gateway sync` で Konnect にデプロイ

**両ファイルをデプロイ:**

```yaml
- name: Sync to Konnect
  run: |
    deck gateway sync \
      kong/configs/bookinfo-kong-generated.yaml \
      kong/configs/global-plugins.yaml \
      --konnect-addr ${{ secrets.KONNECT_ADDR }} \
      --konnect-token ${{ secrets.KONNECT_TOKEN }}
```

---

## 📋 OpenAPI 仕様の書き方

### パスレベル servers オーバーライド (重要!)

Kong で複数のサービスを生成するには、**各 path に servers を定義**します。

**✅ 正しい例:**

```yaml
paths:
  /products:
    get:
      tags:
        - products
      # ← パスレベルで servers を定義
      servers:
        - url: http://productpage.bookinfo.svc.cluster.local:9080/api/v1

  /details/{id}:
    get:
      tags:
        - details
      # ← 別のサービス
      servers:
        - url: http://details.bookinfo.svc.cluster.local:9080
```

**❌ 間違った例:**

```yaml
# グローバル servers のみ (すべてのパスが同じサービスになる)
servers:
  - url: http://productpage.bookinfo.svc.cluster.local:9080

paths:
  /products:
    get:
      tags:
        - products
  /details/{id}:
    get:
      tags:
        - details
```

### `/api/v1` プレフィックスの扱い

**重要:** `/api/v1` は `servers.url` に含め、`paths` には含めません。

**✅ 正しい例:**

```yaml
paths:
  /products: # ← プレフィックスなし
    get:
      servers:
        - url: http://productpage.bookinfo.svc.cluster.local:9080/api/v1 # ← ここに含める
```

**生成される Kong Service:**

```yaml
services:
  - name: bookinfo-api_products
    url: http://productpage.bookinfo.svc.cluster.local:9080
    path: /api/v1 # ← 自動的に path に設定される
    routes:
      - name: bookinfo-api_products
        paths:
          - ~/products$ # ← クライアントリクエスト: GET /products
```

**リクエストフロー:**

```
クライアント: GET http://localhost:8000/products
      ↓
Kong Route: /products にマッチ
      ↓
Kong Service: http://productpage:9080/api/v1/products にプロキシ
      ↓
Bookinfo: GET /api/v1/products
```

---

## 🔍 トラブルシューティング

### `deck file openapi2kong` が失敗する

```bash
# OpenAPI 仕様の検証
deck file openapi2kong --spec kong/specs/openapi.yaml

# エラーメッセージを確認
# → "servers must be defined at path level" などのエラーが表示される
```

**よくある原因:**

- パスレベルの `servers` が定義されていない
- OpenAPI 仕様が無効

### `deck gateway sync` が失敗する

```bash
# 差分確認
deck gateway diff bookinfo-kong-generated.yaml global-plugins.yaml \
  --konnect-addr https://b9b1351cc2.us.cp.konghq.com \
  --konnect-token $KONNECT_TOKEN

# エラーメッセージを確認
```

**よくある原因:**

- `KONNECT_TOKEN` が無効
- ネットワーク接続の問題
- Konnect Control Plane がダウン

### 生成された Kong 設定を確認

```bash
# 生成されたファイルを確認
cat kong/configs/bookinfo-kong-generated.yaml

# Services の数を確認
yq eval '.services | length' kong/configs/bookinfo-kong-generated.yaml

# Service 名のリストを確認
yq eval '.services[].name' kong/configs/bookinfo-kong-generated.yaml
```

---

## 📚 参考リンク

- [deck CLI Documentation](https://docs.konghq.com/deck/latest/)
- [deck file openapi2kong](https://docs.konghq.com/deck/latest/guides/openapi/)
- [Kong Declarative Configuration](https://docs.konghq.com/gateway/latest/production/deployment-topologies/db-less-and-declarative-config/)
- [OpenAPI 3.0 Specification](https://swagger.io/specification/)

---

## ⚠️ 重要な注意事項

1. **`bookinfo-kong-generated.yaml` は手動編集禁止**

   - 常に `deck file openapi2kong` で再生成してください
   - 手動編集は次の生成時に上書きされます

2. **関心の分離**

   - API 仕様: `openapi.yaml`
   - インフラストラクチャプラグイン: `global-plugins.yaml`
   - 混在させないこと

3. **`deck gateway sync` は完全上書き**

   - 両ファイルを一緒に sync すること
   - 片方だけ sync すると設定が消える可能性あり

4. **バージョン管理**
   - `openapi.yaml` と `global-plugins.yaml` は Git で管理
   - `bookinfo-kong-generated.yaml` も Git にコミット (自動生成の履歴追跡のため)
   - `konnect-export.yaml` は `.gitignore` に含める (参考用のため)
