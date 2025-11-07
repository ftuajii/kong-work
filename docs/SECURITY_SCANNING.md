# コンテナセキュリティスキャン

## 概要

このプロジェクトでは、**Trivy**を使用してコンテナイメージの脆弱性スキャンを自動化しています。

## 🔍 スキャン対象

### Kong Gateway ゴールデンイメージ

- **イメージ**: `ghcr.io/ftuajii/bookinfo/kong-gateway:3.10`
- **頻度**: コード変更時 + 毎週月曜日 9:00 JST
- **重要度**: 最優先 (本番環境で使用)
- **スキャン範囲**: CRITICAL/HIGH/MEDIUM 脆弱性

## 🚀 ワークフロー

### 自動実行タイミング

```yaml
# 1. コード変更時 (main ブランチ)
on:
  push:
    branches: [main]
    paths:
      - 'Dockerfile'
      - 'kong/**'

# 2. プルリクエスト作成時
on:
  pull_request:
    branches: [main]

# 3. 定期実行 (毎週月曜 9:00 JST)
on:
  schedule:
    - cron: '0 0 * * 1'

# 4. 手動実行
on:
  workflow_dispatch:
```

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

### Kong Gateway イメージのスキャン

```bash
# 基本スキャン
trivy image ghcr.io/ftuajii/bookinfo/kong-gateway:3.10

# CRITICAL/HIGH のみ表示
trivy image --severity CRITICAL,HIGH ghcr.io/ftuajii/bookinfo/kong-gateway:3.10

# JSON形式で出力
trivy image --format json --output kong-scan.json ghcr.io/ftuajii/bookinfo/kong-gateway:3.10

# HTML レポート生成
trivy image --format template --template "@contrib/html.tpl" \
  --output kong-report.html \
  ghcr.io/ftuajii/bookinfo/kong-gateway:3.10
```

## 🔧 脆弱性への対応方法

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
RUN apk update && apk upgrade
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

- 毎週月曜のスキャン結果を確認
- CRITICAL/HIGH の対応計画を策定

### 月次レポート

- 脆弱性トレンドの分析
- 対応完了率の測定
- セキュリティポリシーの見直し

## 🔗 参考リンク

- [Trivy 公式ドキュメント](https://aquasecurity.github.io/trivy/)
- [GitHub Code Scanning](https://docs.github.com/en/code-security/code-scanning)
- [Kong Security Best Practices](https://docs.konghq.com/gateway/latest/production/security/)
- [NIST NVD (脆弱性データベース)](https://nvd.nist.gov/)

## 🎯 ベストプラクティス

1. **✅ 定期的なスキャン**: 週次または変更時に実施
2. **✅ 優先度付け**: CRITICAL → HIGH → MEDIUM の順で対応
3. **✅ ドキュメント化**: 脆弱性と対応履歴を記録
4. **✅ 自動化**: CI/CD パイプラインに組み込む
5. **✅ 継続的改善**: スキャン結果を次回のビルドに反映
