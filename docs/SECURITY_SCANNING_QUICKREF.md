# セキュリティスキャン クイックリファレンス

## 🚀 すぐに試す

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
```

## 📊 スキャン結果の見方

### ターミナル出力例

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

### GitHub Security タブ

1. Repository → **Security** タブ
2. **Code scanning** をクリック
3. スキャン結果一覧を確認
4. 各脆弱性の詳細、影響範囲、修正方法を確認

## 🎯 主要コマンド

### 基本スキャン

```bash
# テーブル形式で表示
trivy image IMAGE_NAME

# JSON形式で出力
trivy image --format json -o results.json IMAGE_NAME

# HTML レポート生成
trivy image --format template --template "@contrib/html.tpl" \
  -o report.html IMAGE_NAME
```

### 重要度フィルター

```bash
# CRITICALのみ
trivy image --severity CRITICAL IMAGE_NAME

# CRITICAL + HIGH
trivy image --severity CRITICAL,HIGH IMAGE_NAME

# すべての重要度
trivy image --severity CRITICAL,HIGH,MEDIUM,LOW IMAGE_NAME
```

### 特定タイプの脆弱性のみスキャン

```bash
# OS パッケージのみ
trivy image --scanners vuln IMAGE_NAME

# 設定ミスもチェック
trivy image --scanners vuln,config IMAGE_NAME

# シークレット検出も含む
trivy image --scanners vuln,config,secret IMAGE_NAME
```

## 🔧 よく使う組み合わせ

### 1. CI/CD で使う簡易チェック

```bash
# CRITICAL/HIGHがあればfail (exit code 1)
trivy image --exit-code 1 --severity CRITICAL,HIGH IMAGE_NAME
```

### 2. 詳細レポート生成

```bash
# JSON + 表形式の両方
trivy image --format json -o scan.json IMAGE_NAME
trivy image --format table IMAGE_NAME
```

### 3. 複数バージョンを一括スキャン

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

## 🚨 緊急対応フロー

### CRITICAL 脆弱性が見つかった場合

```bash
# 1. 詳細確認
trivy image --severity CRITICAL --format json IMAGE_NAME | jq '.Results[].Vulnerabilities[] | select(.Severity=="CRITICAL")'

# 2. 影響範囲を確認
# - どのパッケージか?
# - 修正バージョンはあるか?
# - CVE詳細を確認 (https://nvd.nist.gov/)

# 3. 修正
# Option A: ベースイメージを更新
# Option B: パッケージを個別更新
# Option C: 代替パッケージを使用

# 4. 再スキャン
trivy image --severity CRITICAL NEW_IMAGE_NAME

# 5. 修正できない場合は .trivyignore に追加 (要承認)
echo "CVE-YYYY-XXXXX  # 理由: ..." >> .trivyignore
```

## 📋 定期メンテナンス

### 毎週月曜 (自動実行後)

```bash
# 1. GitHub Security タブで結果確認
# 2. 新規CRITICAL/HIGHがあれば対応計画作成
# 3. Issueを起票して追跡
```

### 毎月末

```bash
# 1. .trivyignore の見直し
# 2. 無視している脆弱性の再評価
# 3. 修正済みエントリの削除
```

## 🔗 便利なリンク

### スキャン結果の詳細確認

- **NVD (National Vulnerability Database)**: https://nvd.nist.gov/
- **CVE Details**: https://www.cvedetails.com/
- **Trivy DB**: https://github.com/aquasecurity/trivy-db

### Trivy ドキュメント

- **公式ドキュメント**: https://aquasecurity.github.io/trivy/
- **フィルタリング**: https://aquasecurity.github.io/trivy/latest/docs/configuration/filtering/
- **CI/CD 統合**: https://aquasecurity.github.io/trivy/latest/tutorials/integrations/

### Kong Security

- **Kong Security**: https://docs.konghq.com/gateway/latest/production/security/
- **Kong CVE**: https://konghq.com/security

## 💡 Tips

### イメージサイズを小さくして脆弱性を減らす

```dockerfile
# Bad: 大きなベースイメージ
FROM ubuntu:latest

# Good: 小さなベースイメージ
FROM alpine:3.18

# Better: Distroless (最小限のパッケージ)
FROM gcr.io/distroless/base
```

### マルチステージビルドで不要なパッケージを除外

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

### パッケージを最新に保つ

```dockerfile
FROM alpine:3.18
RUN apk update && \
    apk upgrade && \
    apk add --no-cache curl openssl && \
    rm -rf /var/cache/apk/*
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
trivy image --skip-db-update IMAGE_NAME

# 軽量スキャン (OS パッケージのみ)
trivy image --scanners vuln IMAGE_NAME
```

### GitHub Actions でタイムアウト

```yaml
# timeout を延長
- name: Run Trivy scan
  timeout-minutes: 30 # デフォルトは360分だが明示的に設定
  uses: aquasecurity/trivy-action@master
```
