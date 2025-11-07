# GitHub Actions - Konnect 自動デプロイ

## 🔧 セットアップ

### 1. GitHub Secrets の設定

リポジトリの Settings → Secrets and variables → Actions で以下の Secret を追加:

| Secret 名                    | 説明                          | 取得方法                            |
| ---------------------------- | ----------------------------- | ----------------------------------- |
| `KONNECT_TOKEN`              | Konnect Personal Access Token | [取得手順](#konnect-tokenの取得)    |
| `KONNECT_CONTROL_PLANE_NAME` | Control Plane 名              | Konnect UI → Gateway Manager で確認 |

#### KONNECT_TOKEN の取得

1. https://cloud.konghq.com/ にアクセス
2. 右上のアイコン → **Personal Access Tokens**
3. **Generate Token** をクリック
4. トークン名を入力（例: `github-actions-deploy`）
5. 生成されたトークンをコピー
6. GitHub Secrets に `KONNECT_TOKEN` として保存

#### KONNECT_CONTROL_PLANE_NAME の確認

1. Konnect UI → **Gateway Manager**
2. 使用している Control Plane の名前を確認（例: `default`, `production`）
3. GitHub Secrets に `KONNECT_CONTROL_PLANE_NAME` として保存

### 2. ワークフローの動作

#### トリガー条件

以下のいずれかが `main` ブランチに push された時:

- `kong/configs/kong.yaml` の変更
- ワークフローファイル自体の変更

#### 実行ステップ

1. **Checkout**: コードをチェックアウト
2. **Setup deck**: deck CLI をインストール
3. **Validate**: 設定ファイルの妥当性チェック
4. **Show diff**: 変更内容をプレビュー（Dry-run）
5. **Deploy**: Konnect へ設定を同期
6. **Success**: デプロイ成功メッセージ

## 🔄 使い方

### 通常のワークフロー

```bash
# 1. 設定を編集
vim kong/configs/kong.yaml

# 2. ローカルで検証（オプション）
deck gateway validate --state kong/configs/kong.yaml

# 3. Git commit & push
git add kong/configs/kong.yaml
git commit -m "feat: Add new route for /api/users"
git push origin main

# 4. GitHub Actionsが自動実行される
# https://github.com/your-org/kong-work/actions で進捗確認
```

### 安全なデプロイ（Pull Request 推奨）

```bash
# 1. ブランチを作成
git checkout -b feature/add-user-api

# 2. 設定を編集
vim kong/configs/kong.yaml

# 3. Commit & Push
git add kong/configs/kong.yaml
git commit -m "feat: Add new route for /api/users"
git push origin feature/add-user-api

# 4. Pull Request作成 → レビュー → Merge
# Mergeされた時点でmainへのpushとなり、自動デプロイが実行される
```

## 📊 モニタリング

### GitHub Actions の確認

1. リポジトリの **Actions** タブ
2. **Deploy to Konnect** ワークフロー選択
3. 各ステップのログを確認

### デプロイ結果の確認

1. **Konnect UI** → Gateway Manager → 使用している Control Plane
2. Services, Routes, Plugins が更新されていることを確認

## ⚠️ 注意事項

### セキュリティ

- `KONNECT_TOKEN` は絶対にコードにコミットしない
- GitHub Secrets で安全に管理する
- トークンの権限は必要最小限に

### デプロイの影響範囲

- `deck gateway sync` は Konnect の設定を `kong.yaml` の内容で**完全に上書き**
- yaml に含まれていない設定は**削除される**
- 本番環境では必ず Pull Request でレビューしてから merge

### ロールバック

設定に問題があった場合:

```bash
# 1. 前のコミットに戻す
git revert HEAD

# 2. Push（自動的に前の設定がデプロイされる）
git push origin main
```

## 🎯 ベストプラクティス

1. **Pull Request 駆動**: 直接 main に push せず、PR でレビュー
2. **コミットメッセージ**: 変更内容を明確に記載
3. **小さな変更**: 一度に多くの変更を入れない
4. **テスト環境**: 可能なら本番前にステージング環境で検証
5. **バックアップ**: 定期的に現在の設定を `export-konnect-config.sh` でエクスポート
