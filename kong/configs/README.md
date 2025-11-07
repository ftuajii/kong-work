# Kong Configuration as Code (SSoT)

このディレクトリは Kong Gateway の設定の **Single Source of Truth (SSoT)** です。

## 📁 ファイル構成

```
kong/configs/
├── kong.yaml          # Konnectの全設定（Services, Routes, Plugins）
└── README.md          # このファイル
```

## 🔄 ワークフロー

### 1. Konnect から設定をエクスポート（初回/定期的）

```bash
# 環境変数の設定
export KONNECT_TOKEN='your-personal-access-token'
export KONNECT_CONTROL_PLANE_NAME='your-control-plane-name'

# エクスポート実行
./scripts/export-konnect-config.sh
```

**Personal Access Token の取得:**

1. https://cloud.konghq.com/ にアクセス
2. 右上のアイコン → Personal Access Tokens
3. 'Generate Token' をクリック

**Control Plane 名の取得:**

1. Konnect UI → Gateway Manager
2. 使用している Control Plane の名前を確認（例: `default`, `production` など）

### 2. 設定の編集

```bash
# kong.yaml を直接編集
vim kong/configs/kong.yaml
```

**編集可能な要素:**

- Services: バックエンドサービスの定義
- Routes: ルーティングルール
- Plugins: 機能拡張（認証、レート制限、メトリクスなど）

### 3. Konnect へ設定を同期

```bash
# Dry-run（変更内容の確認）
deck gateway diff \
  --konnect-token "$KONNECT_TOKEN" \
  --konnect-control-plane-name "$KONNECT_CONTROL_PLANE_NAME" \
  --state kong/configs/kong.yaml

# 実際に適用
deck gateway sync \
  --konnect-token "$KONNECT_TOKEN" \
  --konnect-control-plane-name "$KONNECT_CONTROL_PLANE_NAME" \
  --state kong/configs/kong.yaml
```

## 🎯 SSoT 運用のメリット

1. **バージョン管理**: Git で設定変更を追跡
2. **レビュー**: Pull Request で変更をレビュー
3. **ロールバック**: 過去の設定に簡単に戻せる
4. **再現性**: 環境を簡単に複製可能
5. **ドキュメント**: 設定がコードとして文書化される
6. **自動デプロイ**: GitHub Actions で main ブランチへの push 時に自動デプロイ

## 🚀 GitHub Actions による自動デプロイ

### セットアップ

1. **GitHub Secrets を設定** (リポジトリの Settings → Secrets and variables → Actions):

   - `KONNECT_TOKEN`: Personal Access Token
   - `KONNECT_CONTROL_PLANE_NAME`: Control Plane 名

2. **ワークフロー**: `.github/workflows/deploy-to-konnect.yml`
   - `kong/configs/kong.yaml` が main に push されると自動実行
   - Validate → Diff → Sync の順で安全にデプロイ

詳細は [.github/README.md](../../.github/README.md) を参照

## 注意事項

- このプロジェクトは Konnect CP 接続用 Data Plane として構成されています
- 設定は Konnect CP で管理することが推奨されます
- `deck gateway sync` は設定を**完全に上書き**するため、本番環境では必ず PR でレビュー
