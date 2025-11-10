# Kong Konnect Dev Portal - API Spec 公開

このディレクトリには、Kong Konnect Dev Portal に API 仕様を公開するためのスクリプトと GitHub Actions ワークフローが含まれています。

## 📋 概要

Kong Konnect の Dev Portal では、API 仕様を「API Product」という単位で管理します。このスクリプトは、OpenAPI 仕様を Konnect API を通じて自動的に登録・公開します。

## 🚀 使い方

### ローカル環境から実行する場合

#### 1. 必要な環境変数を設定

```bash
# Konnect Personal Access Token
export KONNECT_TOKEN='your-konnect-token'

# API Product ID
export API_PRODUCT_ID='your-api-product-id'

# API Product Version ID
export VERSION_ID='your-version-id'

# (オプション) Konnect API Endpoint (デフォルト: https://us.api.konghq.com)
export KONNECT_API_ENDPOINT='https://us.api.konghq.com'

# (オプション) API Specファイルのパス (デフォルト: kong/specs/openapi.yaml)
export SPEC_FILE='kong/specs/openapi.yaml'

# (オプション) API Product Versionを公開状態にする
export PUBLISH_VERSION='true'
```

#### 2. スクリプトを実行

```bash
./scripts/publish-api-spec.sh
```

### GitHub Actions で自動実行する場合

#### 1. GitHub Secrets を設定

リポジトリの Settings → Secrets and variables → Actions で以下の Secret を追加:

- `KONNECT_TOKEN`: Konnect Personal Access Token
- `API_PRODUCT_ID`: API Product ID
- `VERSION_ID`: API Product Version ID

#### 2. (オプション) Variables を設定

デフォルト以外の Konnect API Endpoint を使用する場合:

- `KONNECT_API_ENDPOINT`: Konnect API Endpoint (例: `https://eu.api.konghq.com`)

#### 3. ワークフローの実行

##### 自動実行

`kong/specs/openapi.yaml` を変更して `main` ブランチにプッシュすると、以下の順で自動実行されます:

1. **セキュリティスキャン** (`security-scan.yml`) - Kong Gateway イメージの脆弱性チェック
2. **API Spec 公開** (`publish-api-spec.yml`) - Konnect Dev Portal に仕様を公開
3. **Kong デプロイ** (`deploy-to-konnect.yml`) - サービスとルートを Konnect に反映

**注意**: セキュリティスキャンが失敗すると、後続の API Spec 公開と Kong デプロイは実行されません。

##### 手動実行

1. GitHub リポジトリの Actions タブを開く
2. "Publish API Spec to Konnect Dev Portal" ワークフローを選択
3. "Run workflow" ボタンをクリック
4. 必要に応じて "API Product Version を公開状態にする" オプションを選択
5. "Run workflow" を実行

## 🔑 必要な情報の取得方法

### Konnect Personal Access Token

1. [Kong Konnect Console](https://cloud.konghq.com/) にログイン
2. 右上のユーザーアイコンをクリック
3. "Personal Access Tokens" を選択
4. "Generate Token" をクリック
5. トークン名を入力し、必要な権限を選択
6. 生成されたトークンをコピー (一度しか表示されません!)

### API Product ID

1. [Konnect Console](https://cloud.konghq.com/) にアクセス
2. "API Products" メニューを選択
3. 対象の API Product をクリック
4. URL または詳細画面から ID を確認 (例: `https://cloud.konghq.com/api-products/{API_PRODUCT_ID}`)

### API Product Version ID

1. [Konnect Console](https://cloud.konghq.com/) にアクセス
2. "API Products" → 対象の Product を選択
3. "Product Versions" タブをクリック
4. 対象の Version を選択
5. URL または詳細画面から Version ID を確認

## 📄 スクリプトの動作

`publish-api-spec.sh` スクリプトは以下の処理を実行します:

1. **環境変数のチェック**: 必要な環境変数が設定されているか確認
2. **Base64 エンコード**: OpenAPI Spec ファイルの内容を Base64 エンコード
3. **Specification 登録**: Konnect API 経由で Specification を登録
4. **Version 公開** (オプション): API Product Version を公開状態に更新

## 🔍 トラブルシューティング

### エラー: "API Spec ファイルが見つかりません"

- `SPEC_FILE` 環境変数が正しいパスを指しているか確認
- ファイルが存在することを確認

### エラー: "Specification 登録失敗"

- `KONNECT_TOKEN` が有効か確認
- `API_PRODUCT_ID` と `VERSION_ID` が正しいか確認
- Konnect API のレート制限に達していないか確認

### エラー: "Version 公開失敗"

- API Product Version がすでに公開されている可能性があります
- Konnect UI から手動で状態を確認してください

## 📚 関連ドキュメント

- [Kong Konnect API Documentation](https://docs.konghq.com/konnect/api/)
- [Kong Konnect Dev Portal](https://docs.konghq.com/konnect/dev-portal/)
- [API Products](https://docs.konghq.com/konnect/api-products/)

## 💡 ヒント

### CI/CD パイプラインでの使用

このスクリプトは、CI/CD パイプラインに組み込まれており、API 仕様の変更を自動的に Dev Portal に反映します。

**ワークフロー構成**:

```
OpenAPI変更 (kong/specs/openapi.yaml)
    ↓
セキュリティスキャン (security-scan.yml)
    ↓ (成功時のみ)
API Spec公開 (publish-api-spec.yml)
    ↓
Kong設定デプロイ (deploy-to-konnect.yml)
```

セキュリティスキャンは以下のタイミングで実行されます:

- API Spec 公開と Kong デプロイの前に自動実行
- 毎週月曜日 9:00 JST (定期実行)
- 手動実行 (Actions → "Container Security Scan")

### バージョン管理

API Product Version を適切に管理することで、複数のバージョンの API 仕様を同時に公開できます。例えば:

- `v1`: 現在の本番環境用
- `v2`: 次期バージョン (ベータ)
- `v3`: 開発中

### 複数の API Spec

複数の API 仕様を管理する場合は、`SPEC_FILE` 環境変数を変更して、それぞれのファイルに対してスクリプトを実行してください。

```bash
SPEC_FILE=kong/specs/petstore-api.yaml ./scripts/publish-api-spec.sh
SPEC_FILE=kong/specs/flight-api.yaml ./scripts/publish-api-spec.sh
```
