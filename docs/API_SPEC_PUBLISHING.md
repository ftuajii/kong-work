# Kong Konnect Dev Portal - API Spec 公開

このディレクトリには、Kong Konnect Dev Portal に API 仕様を公開するためのスクリプトと GitHub Actions ワークフローが含まれています。

## 📋 概要

Kong Konnect の Dev Portal では、API 仕様を「API」という単位で管理します（v3 API 使用）。このスクリプトは、OpenAPI 仕様を Konnect API v3 を通じて自動的に登録・公開します。

### 🆕 最新の更新 (2025 年 11 月 19 日)

- **Kong Konnect API v3 への移行完了**
  - エンドポイント: `/v2/api-products` → `/v3/apis`
  - ペイロード構造: `{version, spec: {content: "<JSON文字列>"}}`形式に変更
- **自動作成機能の実装**

  - API が存在しない場合、自動的に新規作成
  - Version が存在しない場合、自動的に新規作成
  - API 名または API ID での指定が可能

- **Python 依存の削除**

  - YAML→JSON 変換を`yq`ツールに切り替え
  - 依存関係の簡素化

- **Current Version 自動更新**

  - 新規 Version 作成時に自動的に Current Version を更新
  - Dev Portal に最新バージョンが常に反映

- **スクリプトのリファクタリング**
  - コード量を約 39%削減 (697 行 → 422 行)
  - 共通関数化により保守性向上
  - 重複コードの削減

## 🚀 使い方

### 必須ツール

- `curl` - API 通信
- `jq` - JSON パース
- `yq` (v4.48.2 以上) - YAML→JSON 変換

```bash
# macOSの場合
brew install yq
```

### ローカル環境から実行する場合

#### 1. 必要な環境変数を設定

```bash
# Konnect Personal Access Token (必須)
export KONNECT_TOKEN='your-konnect-token'

# API ID または API名 (必須)
# - 既存APIのID: export API_PRODUCT_ID='existing-api-id'
# - 既存APIの名前: export API_PRODUCT_ID='existing-api-name'
# - 新規API名: export API_PRODUCT_ID='new-api-name'
export API_PRODUCT_ID='bookinfo'

# Version ID (オプション - 未指定の場合は自動作成/選択)
# export VERSION_ID='your-version-id'

# (オプション) Konnect API Endpoint (デフォルト: https://us.api.konghq.com)
export KONNECT_API_ENDPOINT='https://us.api.konghq.com'

# (オプション) API Specファイルのパス (デフォルト: kong/specs/openapi.yaml)
export SPEC_FILE='kong/specs/openapi.yaml'

# (オプション) Versionを公開状態にする
export PUBLISH_VERSION='true'

# (オプション) 自動Version選択
export AUTO_SELECT_VERSION='true'
```

#### 2. スクリプトを実行

```bash
./scripts/publish-api-spec.sh
```

### 自動作成モード

VERSION_ID を指定しない場合、スクリプトは以下のように動作します:

1. **API が存在しない場合**: 新規作成
2. **Version が存在しない場合**: OpenAPI 仕様のバージョン番号で新規作成
3. **同名 Version が存在する場合**: 既存 Version を更新
4. **Current Version の自動更新**: 常に最新バージョンに更新

### GitHub Actions で自動実行する場合

#### 1. GitHub Secrets を設定

リポジトリの Settings → Secrets and variables → Actions で以下の Secret を追加:

- `KONNECT_TOKEN`: Konnect Personal Access Token
- `API_PRODUCT_ID`: API Product ID
- `VERSION_ID`: API Product Version ID

### GitHub Actions で自動実行する場合

#### 1. GitHub Secrets を設定

リポジトリの Settings → Secrets and variables → Actions で以下の Secret を追加:

- `KONNECT_TOKEN`: Konnect Personal Access Token

**注意**: v3 API では`VERSION_ID`は不要です。OpenAPI 仕様ファイルの`info.version`が自動的に使用されます。

#### 2. (オプション) Variables を設定

デフォルト以外の Konnect API Endpoint を使用する場合:

- `KONNECT_API_ENDPOINT`: Konnect API Endpoint (例: `https://eu.api.konghq.com`)

#### 3. ワークフローの実行

##### 自動実行

`kong/specs/openapi.yaml` を変更して `main` ブランチにプッシュすると、以下の順で自動実行されます:

1. **セキュリティスキャン** (`security-scan.yml`) - Kong Gateway イメージの脆弱性チェック
2. **API Spec 公開** (`publish-api-spec.yml`) - Konnect Dev Portal に仕様を公開
   - OpenAPI 仕様の`info.version`がバージョン名として使用されます
   - 同名バージョンが存在する場合は更新、存在しない場合は新規作成
   - Current Version が自動的に更新されます
3. **Kong デプロイ** (`deploy-to-konnect.yml`) - サービスとルートを Konnect に反映

**注意**: セキュリティスキャンが失敗すると、後続の API Spec 公開と Kong デプロイは実行されません。

##### 手動実行

1. GitHub リポジトリの Actions タブを開く
2. "Publish API Spec to Konnect Dev Portal" ワークフローを選択
3. "Run workflow" ボタンをクリック
4. "Run workflow" を実行

## 🔑 必要な情報の取得方法

### Konnect Personal Access Token

1. [Kong Konnect Console](https://cloud.konghq.com/) にログイン
2. 右上のユーザーアイコンをクリック
3. "Personal Access Tokens" を選択
4. "Generate Token" をクリック
5. トークン名を入力し、必要な権限を選択
6. 生成されたトークンをコピー (一度しか表示されません!)

### API ID

v3 API では、API 名または API ID で指定できます:

**方法 1: 既存 API の確認**

1. [Konnect Console](https://cloud.konghq.com/) にアクセス
2. "APIs" メニューを選択
3. 対象の API をクリック
4. URL または詳細画面から ID を確認 (例: `https://cloud.konghq.com/apis/{API_ID}`)

**方法 2: API 名で指定**

- API 名を`API_PRODUCT_ID`環境変数に設定すると、自動的に ID が解決されます
- 存在しない場合は、その名前で新規 API が作成されます

### API Version

v3 API では、OpenAPI 仕様ファイルの`info.version`が自動的に使用されます。

```yaml
# kong/specs/openapi.yaml
openapi: 3.1.0
info:
  title: BookInfo API
  version: 1.0.3 # ← このバージョンが使用されます
```

## 📄 スクリプトの動作

`publish-api-spec.sh` スクリプトは以下の処理を実行します（Kong Konnect API v3 使用）:

1. **環境変数のチェック**: 必要な環境変数が設定されているか確認
2. **API Spec の読み込み**: OpenAPI 仕様ファイルを読み込み、バージョン情報を抽出
3. **API の確認/作成**:
   - 指定された API ID または API 名で API を検索
   - 存在しない場合は自動的に新規 API 作成
4. **Version の確認/作成**:
   - OpenAPI 仕様の`info.version`と同名の Version を検索
   - 存在する場合は更新、存在しない場合は新規作成
5. **仕様書の登録/更新**:
   - YAML→JSON 変換（`yq`使用）
   - Konnect API v3 経由で Specification を登録
   - ペイロード形式: `{version: "x.y.z", spec: {content: "<JSON文字列>"}}`
6. **Current Version の更新**: Dev Portal に最新バージョンを反映
7. **Version 公開** (オプション): Version を公開状態に更新

### 主要な関数

- `find_yq_command()` - yq コマンドの検索
- `convert_yaml_to_json()` - YAML→JSON 変換
- `update_current_version()` - Current Version 更新
- `publish_version()` - Version 公開
- `show_completion_message()` - 完了メッセージ表示

## 🔍 トラブルシューティング

### エラー: "yq コマンドが見つかりません"

```bash
# macOSの場合
brew install yq

# インストール確認
yq --version  # v4.48.2以上
```

### エラー: "API Spec ファイルが見つかりません"

- `SPEC_FILE` 環境変数が正しいパスを指しているか確認
- ファイルが存在することを確認

### エラー: "YAML to JSON 変換に失敗"

- OpenAPI 仕様ファイルの YAML 構文が正しいか確認
- yq のバージョンが v4.48.2 以上であることを確認

### エラー: "API 作成失敗" または "Version 作成失敗"

- `KONNECT_TOKEN` が有効か確認
- トークンに適切な権限があるか確認
- Konnect API のレート制限に達していないか確認

### Current Version が更新されない

スクリプトは自動的に Current Version を更新しますが、以下を確認してください:

- Dev Portal でバージョンが正しく表示されているか
- Konnect UI で手動確認: APIs → 対象 API → Current Version

### Dev Portal の Upstream URL が間違っている

OpenAPI 仕様の`x-kong-service-defaults`を確認:

```yaml
x-kong-service-defaults:
  host: productpage.bookinfo.svc.cluster.local
  port: 9080
  path: /api/v1
```

設定後、`deck sync`で反映:

```bash
deck gateway sync kong/configs/final-kong.yaml \
  --konnect-token $KONNECT_TOKEN \
  --konnect-control-plane-name kong-work
```

## 📚 関連ドキュメント

- [Kong Konnect API v3 Documentation](https://docs.konghq.com/konnect/api/)
- [Kong Konnect Dev Portal](https://docs.konghq.com/konnect/dev-portal/)
- [Kong Gateway OpenAPI Extensions](https://docs.konghq.com/gateway/latest/reference/openapi-extensions/)

## 💡 ヒント

### バージョン管理のベストプラクティス

OpenAPI 仕様の`info.version`を適切に管理することで、スムーズなバージョン管理が可能です:

```yaml
# 開発中
info:
  version: 1.0.4-beta

# リリース準備
info:
  version: 1.0.4

# 本番リリース
info:
  version: 1.0.4  # スクリプト実行でCurrent Versionが自動更新
```

### Dev Portal URL と Gateway Upstream URL の分離

OpenAPI 仕様では、開発者向けと実際のゲートウェイ向けで異なる URL を設定できます:

```yaml
# 開発者がDev Portalで見るURL
servers:
  - url: http://localhost:8000
    description: Kong Gateway (Local)

# 実際のKong Gatewayが使用するUpstream
x-kong-service-defaults:
  host: productpage.bookinfo.svc.cluster.local
  port: 9080
  path: /api/v1
```

### CI/CD パイプラインでの使用

このスクリプトは、CI/CD パイプラインに組み込まれており、API 仕様の変更を自動的に Dev Portal に反映します。

**ワークフロー構成**:

```
OpenAPI変更 (kong/specs/openapi.yaml)
    ↓
セキュリティスキャン (security-scan.yml)
    ↓ (成功時のみ)
API Spec公開 (publish-api-spec.yml)
    ├─ OpenAPI仕様のバージョンを自動検出
    ├─ Version自動作成/更新
    └─ Current Version自動更新
    ↓
Kong設定デプロイ (deploy-to-konnect.yml)
```

セキュリティスキャンは以下のタイミングで実行されます:

- API Spec 公開と Kong デプロイの前に自動実行
- 毎週月曜日 9:00 JST (定期実行)
- 手動実行 (Actions → "Container Security Scan")

### 複数の API の管理

複数の API 仕様を管理する場合は、`API_PRODUCT_ID` と `SPEC_FILE` を変更して実行します:

```bash
# BookInfo API
export API_PRODUCT_ID='bookinfo'
export SPEC_FILE='kong/specs/bookinfo-api.yaml'
./scripts/publish-api-spec.sh

# PetStore API
export API_PRODUCT_ID='petstore'
export SPEC_FILE='kong/specs/petstore-api.yaml'
./scripts/publish-api-spec.sh
```

### Version 更新の確認

Version 更新後、以下で確認できます:

1. **Dev Portal**: https://[your-portal].kongportals.com/apis/[api-name]
2. **Konnect UI**: APIs → 対象 API → Versions
3. **API 経由**:

```bash
curl -s "https://us.api.konghq.com/v3/apis/${API_ID}" \
  -H "Authorization: Bearer ${KONNECT_TOKEN}" | jq '.version'
```
