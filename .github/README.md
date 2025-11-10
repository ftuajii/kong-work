# GitHub Actions - OpenAPI-driven Kong デプロイメント

このディレクトリには Kong 設定の自動デプロイメントワークフローが含まれています。

## 🎯 設計思想

**Single Source of Truth: `kong/specs/openapi.yaml`**

OpenAPI 仕様を変更すると、自動的に Kong 設定が生成され、Konnect にデプロイされます。

```
OpenAPI 仕様の変更 (kong/specs/openapi.yaml)
         ↓
    GitHub Push
         ↓
   GitHub Actions トリガー
         ↓
deck file openapi2kong (Kong 設定生成)
         ↓
deck gateway sync (Konnect デプロイ)
         ↓
    Kong Data Plane
```

---

## 🔧 セットアップ

### 1. GitHub Secrets の設定

リポジトリの Settings → Secrets and variables → Actions で以下の Secret を追加:

| Secret 名       | 説明                           | 取得方法                                  |
| --------------- | ------------------------------ | ----------------------------------------- |
| `KONNECT_ADDR`  | Konnect Control Plane アドレス | 例: `https://b9b1351cc2.us.cp.konghq.com` |
| `KONNECT_TOKEN` | Konnect Personal Access Token  | [取得手順](#konnect-tokenの取得)          |

#### KONNECT_ADDR の確認

1. Konnect UI → Gateway Manager → 使用している Control Plane を選択
2. **Data Plane Nodes** タブ → **New Data Plane Node** をクリック
3. **Step 2: Generate Certificates** に表示される `cluster_control_plane` の値
   - 例: `b9b1351cc2.us.cp.konghq.com:443`
4. `https://` をつけて GitHub Secrets に保存
   - 例: `https://b9b1351cc2.us.cp.konghq.com`

#### KONNECT_TOKEN の取得

1. https://cloud.konghq.com/ にアクセス
2. 右上のアイコン → **Personal Access Tokens**
3. **Generate Token** をクリック
4. トークン名を入力（例: `github-actions-deploy`）
5. 生成されたトークンをコピー
6. GitHub Secrets に `KONNECT_TOKEN` として保存

---

## 🔄 ワークフロー

### ワークフロー 1: `deploy-to-konnect.yml`

**トリガー条件:**

- `kong/specs/openapi.yaml` が `main` ブランチに push された時
- `.github/workflows/deploy-to-konnect.yml` 自体が変更された時

**実行ステップ:**

1. **Checkout**: コードをチェックアウト
2. **Setup deck**: deck CLI (v1.49.2) をインストール
3. **Generate Kong config**: `deck file openapi2kong` で Kong 設定を生成
4. **Validate**: 生成された設定ファイルの妥当性チェック
5. **Show diff**: 変更内容をプレビュー（Dry-run）
6. **Deploy**: Konnect へ設定を同期
7. **Success**: デプロイ成功メッセージ

**デプロイされるファイル:**

- `kong/configs/bookinfo-kong-generated.yaml` (自動生成)
- `kong/configs/global-plugins.yaml` (手動管理)

---

## � 使い方

### 1. 新しい API エンドポイントを追加

```bash
# 1. ブランチを作成
git checkout -b feature/add-ratings-api

# 2. OpenAPI 仕様を編集
vim kong/specs/openapi.yaml

# 例: /products/{id}/ratings を追加
# paths:
#   /products/{id}/ratings:
#     get:
#       tags:
#         - ratings
#       servers:
#         - url: http://ratings.bookinfo.svc.cluster.local:9080/api/v1

# 3. ローカルで検証（オプション）
cd kong/specs
deck file openapi2kong --spec openapi.yaml --output-file ../configs/bookinfo-kong-generated.yaml
cd ../configs
deck file validate bookinfo-kong-generated.yaml global-plugins.yaml

# 4. Commit & Push
git add kong/specs/openapi.yaml
git commit -m "feat: Add /products/{id}/ratings endpoint"
git push origin feature/add-ratings-api

# 5. Pull Request作成 → レビュー → Merge
# Mergeされた時点でGitHub Actionsが自動実行される
```

---

### 2. グローバルプラグインを追加

```bash
# 1. ブランチを作成
git checkout -b feature/add-rate-limiting

# 2. global-plugins.yaml を編集
vim kong/configs/global-plugins.yaml

# 例: Rate Limiting プラグインを追加
# plugins:
# - name: rate-limiting
#   config:
#     minute: 100

# 3. ローカルで検証（オプション）
cd kong/configs
deck file validate bookinfo-kong-generated.yaml global-plugins.yaml

# 4. Commit & Push
git add kong/configs/global-plugins.yaml
git commit -m "feat: Add rate-limiting plugin"
git push origin feature/add-rate-limiting

# 5. Pull Request作成 → レビュー → Merge
```

**注意:** `global-plugins.yaml` の変更は自動デプロイされません。`openapi.yaml` も一緒に変更するか、手動で `deck gateway sync` を実行してください。

---

### 3. デプロイ結果の確認

**GitHub Actions:**

1. リポジトリの **Actions** タブ
2. **Deploy to Konnect** ワークフロー選択
3. 各ステップのログを確認

**Konnect UI:**

1. https://cloud.konghq.com/ → Gateway Manager
2. 使用している Control Plane を選択
3. **Gateway Services** で Services/Routes が更新されていることを確認

**Kong Data Plane (ローカル):**

```bash
# API リクエストを送信
curl http://localhost:8000/products
curl http://localhost:8000/products/0/ratings  # 新しいエンドポイント

# Konnect 設定をエクスポートして確認
./scripts/export-konnect-config.sh
cat kong/configs/konnect-export.yaml
```

---

## ⚠️ 注意事項

### セキュリティ

- `KONNECT_TOKEN` は絶対にコードにコミットしない
- GitHub Secrets で安全に管理する
- トークンの権限は必要最小限に

### デプロイの影響範囲

- `deck gateway sync` は Konnect の設定を指定されたファイルの内容で**完全に上書き**
- 両ファイル (`bookinfo-kong-generated.yaml` + `global-plugins.yaml`) を一緒に sync することが重要
- 片方だけ sync すると設定が消える可能性あり

### 自動生成ファイルの扱い

- `bookinfo-kong-generated.yaml` は手動編集禁止
- 常に `deck file openapi2kong` で再生成する
- 手動編集は次の自動生成時に上書きされる

### ロールバック

設定に問題があった場合:

```bash
# 1. 前のコミットに戻す
git revert HEAD

# 2. Push（自動的に前の設定がデプロイされる）
git push origin main
```

または手動で:

```bash
# 過去のコミットから openapi.yaml を復元
git checkout <commit-hash> -- kong/specs/openapi.yaml

# Kong 設定を再生成
cd kong/specs
deck file openapi2kong --spec openapi.yaml --output-file ../configs/bookinfo-kong-generated.yaml

# デプロイ
cd ../configs
deck gateway sync bookinfo-kong-generated.yaml global-plugins.yaml \
  --konnect-addr $KONNECT_ADDR \
  --konnect-token $KONNECT_TOKEN
```

---

## 🎯 ベストプラクティス

1. **Pull Request 駆動開発**

   - 直接 main に push せず、PR でレビュー
   - CI/CD パイプラインで自動検証
   - レビュー承認後に merge

2. **コミットメッセージ**

   - 変更内容を明確に記載
   - 例: `feat: Add /products/{id}/ratings endpoint`
   - 例: `fix: Correct path prefix for details service`

3. **小さな変更を積み重ねる**

   - 一度に多くの変更を入れない
   - 問題発生時のロールバックが容易

4. **ローカルで事前検証**

   - `deck file openapi2kong` で生成
   - `deck file validate` で検証
   - `deck gateway diff` で差分確認

5. **テスト環境の活用**

   - 可能なら本番前にステージング環境で検証
   - ローカル kind クラスターでテスト

6. **定期的なバックアップ**
   - `./scripts/export-konnect-config.sh` で現在の設定をエクスポート
   - Git で履歴管理

---

## 📊 モニタリング

### GitHub Actions の確認

```bash
# 最新のワークフロー実行状態を確認
gh run list --workflow=deploy-to-konnect.yml

# 特定の実行のログを表示
gh run view <run-id>
```

### Konnect デプロイメント履歴

Konnect UI では詳細なデプロイメント履歴は表示されないため、Git コミット履歴で追跡:

```bash
# OpenAPI 仕様の変更履歴
git log --oneline -- kong/specs/openapi.yaml

# 特定のコミットでの openapi.yaml の内容を表示
git show <commit-hash>:kong/specs/openapi.yaml
```

---

## 🔍 トラブルシューティング

### ワークフローが失敗する

```bash
# 1. GitHub Actions ログを確認
# Actions → 失敗したワークフロー → ログを確認

# 2. ローカルで再現
cd kong/specs
deck file openapi2kong --spec openapi.yaml --output-file ../configs/bookinfo-kong-generated.yaml
# → エラーメッセージを確認

# 3. OpenAPI 仕様を修正
vim kong/specs/openapi.yaml

# 4. 再度 push
git add kong/specs/openapi.yaml
git commit -m "fix: Correct OpenAPI specification"
git push
```

### `deck file openapi2kong` が失敗する

**よくあるエラー:**

- "servers must be defined at path level"
  → 各 path に `servers` を定義する

- "invalid OpenAPI specification"
  → OpenAPI 3.0 仕様に準拠しているか確認

### `deck gateway sync` が失敗する

**よくあるエラー:**

- "authentication failed"
  → `KONNECT_TOKEN` が無効または期限切れ
  → 新しいトークンを生成して GitHub Secrets を更新

- "connection refused"
  → `KONNECT_ADDR` が間違っている
  → Konnect UI で正しいアドレスを確認

---

## 📚 参考リンク

- [deck CLI Documentation](https://docs.konghq.com/deck/latest/)
- [deck file openapi2kong Guide](https://docs.konghq.com/deck/latest/guides/openapi/)
- [GitHub Actions Documentation](https://docs.github.com/actions)
- [Kong Konnect Documentation](https://docs.konghq.com/konnect/)
