#!/bin/bash

set -e

# スクリプトのディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🔄 Kong設定の同期"
echo "=============================="
echo ""

# Konnect Personal Access Tokenの確認
if [ -z "$KONNECT_TOKEN" ]; then
  echo "⚠️  KONNECT_TOKEN環境変数が設定されていません"
  echo ""
  echo "📝 Konnect Personal Access Tokenの取得方法:"
  echo "   1. https://cloud.konghq.com/ にアクセス"
  echo "   2. 右上のアイコン → Personal Access Tokens"
  echo "   3. 'Generate Token' をクリック"
  echo "   4. 以下のコマンドでトークンを設定:"
  echo "      export KONNECT_TOKEN='your-token-here'"
  echo ""
  exit 1
fi

echo "✅ KONNECT_TOKEN が設定されています"
echo ""

# Control Plane名の確認
if [ -z "$KONNECT_CONTROL_PLANE_NAME" ]; then
  echo "⚠️  KONNECT_CONTROL_PLANE_NAME環境変数が設定されていません"
  echo ""
  echo "📝 Control Plane名の取得方法:"
  echo "   1. Konnect UI → Gateway Manager"
  echo "   2. 使用しているControl Planeの名前を確認"
  echo "   3. 以下のコマンドで設定:"
  echo "      export KONNECT_CONTROL_PLANE_NAME='your-cp-name-here'"
  echo ""
  echo "   例: export KONNECT_CONTROL_PLANE_NAME='default'"
  echo ""
  exit 1
fi

echo "✅ KONNECT_CONTROL_PLANE_NAME が設定されています"
echo ""

# 1. OpenAPI仕様からKong設定生成
echo "📝 Step 1/4: OpenAPI仕様からKong設定を生成..."
deck file openapi2kong \
  --spec "$ROOT_DIR/kong/specs/openapi.yaml" \
  --output-file "$ROOT_DIR/kong/configs/generated-kong.yaml" \
  --format yaml
echo "✅ Kong config generated successfully!"
echo ""
echo "📋 Generated services:"
grep -E "^- name:" "$ROOT_DIR/kong/configs/generated-kong.yaml" | sed 's/- name:/  -/' || true

echo ""
echo "🔌 Step 2/4: プラグインを追加..."
deck file add-plugins \
  -s "$ROOT_DIR/kong/configs/generated-kong.yaml" \
  "$ROOT_DIR/kong/configs/service-plugins.yaml" \
  -o "$ROOT_DIR/kong/configs/final-kong.yaml"
echo "✅ Plugins added successfully!"

echo ""
echo "📊 Step 3/4: 変更内容を確認 (Dry-run)..."
deck gateway diff \
  --konnect-token "$KONNECT_TOKEN" \
  --konnect-control-plane-name "$KONNECT_CONTROL_PLANE_NAME" \
  "$ROOT_DIR/kong/configs/final-kong.yaml" \
  "$ROOT_DIR/kong/configs/global-plugins.yaml" \
  "$ROOT_DIR/kong/configs/consumers.yaml" || true

echo ""
echo "🚀 Step 4/4: Konnectに同期..."
deck gateway sync \
  --konnect-token "$KONNECT_TOKEN" \
  --konnect-control-plane-name "$KONNECT_CONTROL_PLANE_NAME" \
  "$ROOT_DIR/kong/configs/final-kong.yaml" \
  "$ROOT_DIR/kong/configs/global-plugins.yaml" \
  "$ROOT_DIR/kong/configs/consumers.yaml"

echo ""
echo "✅ Successfully deployed to Konnect!"
echo "📦 Control Plane: $KONNECT_CONTROL_PLANE_NAME"
echo ""
echo "📋 同期された設定:"
echo "   - サービス・ルート (final-kong.yaml)"
echo "   - グローバルプラグイン (global-plugins.yaml)"
echo "   - コンシューマー (consumers.yaml)"
