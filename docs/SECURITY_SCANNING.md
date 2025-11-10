# コンテナセキュリティスキャン

## 概要

このプロジェクトでは、**Trivy**を使用してコンテナイメージの脆弱性スキャンを自動化しています。

## 🚀 クイックスタート

### 1. ワークフローを手動実行

```bash
# GitHub UIから実行:
# Actions → "Container Security Scan" → "Run workflow"
# - Branch: main
# - image_tag: 3.10 (デフォルト)
```

### 2. ローカルで即座にスキャン

```bash
# Trivyインストール
brew install aquasecurity/trivy/trivy

# Kong Gatewayをスキャン
trivy image ghcr.io/ftuajii/bookinfo/kong-gateway:3.10

# CRITICAL/HIGHのみ表示
trivy image --severity CRITICAL,HIGH ghcr.io/ftuajii/bookinfo/kong-gateway:3.10
```

## 🔍 スキャン対象

### Kong Gateway ゴールデンイメージ

- **イメージ**: `ghcr.io/ftuajii/bookinfo/kong-gateway:3.10`
- **頻度**: 他ワークフローから呼び出し + 毎週月曜日 9:00 JST
- **重要度**: 最優先 (本番環境で使用)
- **スキャン範囲**: CRITICAL/HIGH/MEDIUM 脆弱性

## 🚀 ワークフロー

### 自動実行タイミング

```yaml
# 1. 他ワークフローから呼び出し (publish-api-spec.yml, deploy-to-konnect.yml)
on:
  workflow_call:
    inputs:
      image_tag:
        type: string

# 2. 定期実行 (毎週月曜 9:00 JST / 00:00 UTC)
on:
  schedule:
    - cron: '0 0 * * 1'

# 3. 手動実行
on:
  workflow_dispatch:
    inputs:
      image_tag:
        type: string
```

**注意**: セキュリティスキャンが失敗すると、API Spec 公開と Kong デプロイは実行されません。

### スキャン結果の確認方法

#### 1. GitHub Security タブ

- リポジトリの **Security** → **Code scanning** を確認
- SARIF 形式の詳細レポートが表示される
- 脆弱性の優先度、修正方法などが確認可能

#### 2. Actions サマリー

- ワークフロー実行結果に脆弱性の統計が表示される
- CRITICAL/HIGH/MEDIUM の件数がわかる

#### 3. GitHub Step Summary

```markdown
## 🛡️ セキュリティスキャン結果

**イメージ**: `ghcr.io/ftuajii/bookinfo/kong-gateway:3.10`

### 📊 脆弱性サマリー

| 深刻度      | 件数 |
| ----------- | ---- |
| 🔴 CRITICAL | 0    |
| 🟠 HIGH     | 3    |
| 🟡 MEDIUM   | 12   |
```

## 📋 脆弱性レベルの定義

| レベル          | 説明                                         | 対応優先度       |
| --------------- | -------------------------------------------- | ---------------- |
| **🔴 CRITICAL** | リモートコード実行、権限昇格など重大な脆弱性 | **即時対応**     |
| **🟠 HIGH**     | 深刻な影響があるが、悪用条件が限定的         | **1 週間以内**   |
| **🟡 MEDIUM**   | 限定的な影響、または悪用が困難               | **1 ヶ月以内**   |
| **🟢 LOW**      | 軽微な影響                                   | **計画的に対応** |

### スキャン結果の見方

#### ターミナル出力例

```
ghcr.io/ftuajii/bookinfo/kong-gateway:3.10 (alpine 3.18.4)

Total: 23 (CRITICAL: 2, HIGH: 5, MEDIUM: 16, LOW: 0)

┌────────────┬──────────────┬──────────┬────────┬───────────────┐
│  Library   │ Vulnerability│ Severity │ Status │ Installed Ver │
├────────────┼──────────────┼──────────┼────────┼───────────────┤
│ openssl    │ CVE-2024-XXX │ CRITICAL │  fixed │ 3.0.10-r0     │
│ curl       │ CVE-2024-YYY │   HIGH   │  fixed │ 8.4.0-r0      │
└────────────┴──────────────┴──────────┴────────┴───────────────┘
```

## 🛠️ ローカルでのスキャン実行

### Trivy のインストール

```bash
# macOS
brew install aquasecurity/trivy/trivy

# Linux
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
echo "deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee -a /etc/apt/sources.list.d/trivy.list
sudo apt-get update
sudo apt-get install trivy
```

### 主要コマンド

#### 基本スキャン

```bash
# テーブル形式で表示
trivy image ghcr.io/ftuajii/bookinfo/kong-gateway:3.10

# JSON形式で出力
trivy image --format json -o results.json ghcr.io/ftuajii/bookinfo/kong-gateway:3.10

# HTML レポート生成
trivy image --format template --template "@contrib/html.tpl" \
  -o report.html ghcr.io/ftuajii/bookinfo/kong-gateway:3.10
```

#### 重要度フィルター

```bash
# CRITICALのみ
trivy image --severity CRITICAL ghcr.io/ftuajii/bookinfo/kong-gateway:3.10

# CRITICAL + HIGH
trivy image --severity CRITICAL,HIGH ghcr.io/ftuajii/bookinfo/kong-gateway:3.10

# すべての重要度
trivy image --severity CRITICAL,HIGH,MEDIUM,LOW ghcr.io/ftuajii/bookinfo/kong-gateway:3.10
```

#### 特定タイプの脆弱性のみスキャン

```bash
# OS パッケージのみ
trivy image --scanners vuln ghcr.io/ftuajii/bookinfo/kong-gateway:3.10

# 設定ミスもチェック
trivy image --scanners vuln,config ghcr.io/ftuajii/bookinfo/kong-gateway:3.10

# シークレット検出も含む
trivy image --scanners vuln,config,secret ghcr.io/ftuajii/bookinfo/kong-gateway:3.10
```

### よく使う組み合わせ

#### 1. CI/CD で使う簡易チェック

```bash
# CRITICAL/HIGHがあればfail (exit code 1)
trivy image --exit-code 1 --severity CRITICAL,HIGH ghcr.io/ftuajii/bookinfo/kong-gateway:3.10
```

#### 2. 詳細レポート生成

```bash
# JSON + 表形式の両方
trivy image --format json -o scan.json ghcr.io/ftuajii/bookinfo/kong-gateway:3.10
trivy image --format table ghcr.io/ftuajii/bookinfo/kong-gateway:3.10
```

#### 3. 複数バージョンを一括スキャン

```bash
#!/bin/bash
# 複数のタグを一括スキャン
tags=("3.10" "3.9" "3.8")

for tag in "${tags[@]}"; do
  echo "=== Scanning: kong-gateway:${tag} ==="
  trivy image --severity CRITICAL,HIGH "ghcr.io/ftuajii/bookinfo/kong-gateway:${tag}"
  echo ""
done
```

## 🔧 脆弱性への対応方法

### 🚨 緊急対応フロー (CRITICAL 脆弱性)

```bash
# 1. 詳細確認
trivy image --severity CRITICAL --format json ghcr.io/ftuajii/bookinfo/kong-gateway:3.10 | \
  jq '.Results[].Vulnerabilities[] | select(.Severity=="CRITICAL")'

# 2. 影響範囲を確認
# - どのパッケージか?
# - 修正バージョンはあるか?
# - CVE詳細を確認 (https://nvd.nist.gov/)

# 3. 修正
# Option A: ベースイメージを更新
# Option B: パッケージを個別更新
# Option C: 代替パッケージを使用

# 4. 再スキャン
trivy image --severity CRITICAL ghcr.io/ftuajii/bookinfo/kong-gateway:3.10

# 5. 修正できない場合は .trivyignore に追加 (要承認)
echo "CVE-YYYY-XXXXX  # 理由: ..." >> .trivyignore
```

### 1. イメージの更新

```bash
# Kong Gateway の場合
# 最新のベースイメージを使用してリビルド
docker build -t ghcr.io/ftuajii/bookinfo/kong-gateway:3.10 .
docker push ghcr.io/ftuajii/bookinfo/kong-gateway:3.10
```

### 2. 依存パッケージの更新

```dockerfile
# Dockerfile内でパッケージを更新
RUN apk update && apk upgrade && \
    rm -rf /var/cache/apk/*
```

### 3. 脆弱性の無視設定

修正不可能な脆弱性や、誤検知の場合:

```yaml
# .trivyignore ファイルを作成
CVE-2023-XXXXX  # 理由: false positive
CVE-2024-YYYYY  # 理由: 影響なし (使用していない機能)
```

### 4. 代替イメージの検討

公式イメージに脆弱性が多い場合:

- Distroless イメージの使用
- Alpine Linux ベースへの変更
- チームによるカスタムビルド

### セキュリティベストプラクティス

#### イメージサイズを小さくして脆弱性を減らす

```dockerfile
# Bad: 大きなベースイメージ
FROM ubuntu:latest

# Good: 小さなベースイメージ
FROM alpine:3.18

# Better: Distroless (最小限のパッケージ)
FROM gcr.io/distroless/base
```

#### マルチステージビルドで不要なパッケージを除外

```dockerfile
# ビルドステージ
FROM alpine:3.18 AS builder
RUN apk add --no-cache build-tools
COPY . /app
RUN make build

# 実行ステージ (ビルドツールを含まない)
FROM alpine:3.18
COPY --from=builder /app/binary /usr/local/bin/
CMD ["binary"]
```

#### パッケージを最新に保つ

```dockerfile
FROM alpine:3.18
RUN apk update && \
    apk upgrade && \
    apk add --no-cache curl openssl && \
    rm -rf /var/cache/apk/*
```

## 📊 CI/CD での制御

### Pull Request でのゲート制御

```yaml
- name: Check for critical vulnerabilities
  run: |
    CRITICAL=$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity == "CRITICAL")] | length' scan-results.json)

    if [ "${CRITICAL:-0}" -gt 0 ]; then
      echo "❌ CRITICAL脆弱性が見つかりました"
      exit 1  # PRをブロック
    fi
```

### Main ブランチでの警告のみ

```yaml
if [ "${{ github.event_name }}" == "pull_request" ]; then
  exit 1  # PRではfail
else
  echo "⚠️ 警告のみ (main branch)"
fi
```

## 🔔 アラート設定

### GitHub Notifications

- Security → **Code scanning alerts** で通知設定
- CRITICAL/HIGH の場合にメール通知

### Slack 連携 (オプション)

```yaml
- name: Send Slack notification
  if: failure()
  uses: slackapi/slack-github-action@v1
  with:
    webhook-url: ${{ secrets.SLACK_WEBHOOK }}
    payload: |
      {
        "text": "🚨 セキュリティスキャンで脆弱性を検出",
        "blocks": [
          {
            "type": "section",
            "text": {
              "type": "mrkdwn",
              "text": "*Image:* Kong Gateway\n*Severity:* CRITICAL"
            }
          }
        ]
      }
```

## 📈 定期レビュー

### 週次レビュー (推奨)

```bash
# 毎週月曜 (自動実行後)
# 1. GitHub Security タブで結果確認
# 2. 新規CRITICAL/HIGHがあれば対応計画作成
# 3. Issueを起票して追跡
```

### 月次レポート

```bash
# 毎月末
# 1. .trivyignore の見直し
# 2. 無視している脆弱性の再評価
# 3. 修正済みエントリの削除
# 4. 脆弱性トレンドの分析
# 5. 対応完了率の測定
# 6. セキュリティポリシーの見直し
```

## ❓ トラブルシューティング

### "database error: failed to download vulnerability DB"

```bash
# DBを更新
trivy image --download-db-only

# キャッシュをクリア
trivy clean --all
```

### スキャンが遅い

```bash
# オフラインモード (事前にDBダウンロード)
trivy image --download-db-only
trivy image --skip-db-update ghcr.io/ftuajii/bookinfo/kong-gateway:3.10

# 軽量スキャン (OS パッケージのみ)
trivy image --scanners vuln ghcr.io/ftuajii/bookinfo/kong-gateway:3.10
```

### GitHub Actions でタイムアウト

```yaml
# timeout を延長
- name: Run Trivy scan
  timeout-minutes: 30
  uses: aquasecurity/trivy-action@master
```

## 🔗 参考リンク

### スキャン結果の詳細確認

- **NVD (National Vulnerability Database)**: https://nvd.nist.gov/
- **CVE Details**: https://www.cvedetails.com/
- **Trivy DB**: https://github.com/aquasecurity/trivy-db

### Trivy ドキュメント

- **公式ドキュメント**: https://aquasecurity.github.io/trivy/
- **フィルタリング**: https://aquasecurity.github.io/trivy/latest/docs/configuration/filtering/
- **CI/CD 統合**: https://aquasecurity.github.io/trivy/latest/tutorials/integrations/

### Kong & GitHub Security

- **Kong Security**: https://docs.konghq.com/gateway/latest/production/security/
- **Kong CVE**: https://konghq.com/security
- **GitHub Code Scanning**: https://docs.github.com/en/code-security/code-scanning

## 🎯 ベストプラクティス

1. **✅ 定期的なスキャン**: 週次または変更時に実施
2. **✅ 優先度付け**: CRITICAL → HIGH → MEDIUM の順で対応
3. **✅ ドキュメント化**: 脆弱性と対応履歴を記録
4. **✅ 自動化**: CI/CD パイプラインに組み込む
5. **✅ 継続的改善**: スキャン結果を次回のビルドに反映
6. **✅ 最小権限**: 必要なパッケージのみインストール
7. **✅ イメージ最適化**: マルチステージビルドと Distroless 使用
