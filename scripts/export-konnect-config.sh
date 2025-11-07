#!/bin/bash

set -e

echo "🔑 Konnect設定のエクスポート"
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

# エクスポート実行
OUTPUT_FILE="kong/configs/kong.yaml"

echo "📦 Step 1/2: Konnectから設定をエクスポート..."
deck gateway dump \
  --konnect-token "$KONNECT_TOKEN" \
  --konnect-control-plane-name "$KONNECT_CONTROL_PLANE_NAME" \
  --output-file "$OUTPUT_FILE" \
  --format yaml

echo ""
echo "✅ Step 2/2: エクスポート完了"
echo ""
echo "📄 保存先: $OUTPUT_FILE"
echo ""

# エクスポートされた内容のサマリー表示
if [ -f "$OUTPUT_FILE" ]; then
  echo "📊 エクスポートされた設定:"
  echo "   Services: $(grep -c '^- name:' "$OUTPUT_FILE" 2>/dev/null || echo 0)"
  echo "   Routes:   $(grep -c '  - name:' "$OUTPUT_FILE" 2>/dev/null || echo 0)"
  echo "   Plugins:  $(grep -c '    - name:' "$OUTPUT_FILE" 2>/dev/null || echo 0)"
  echo ""
  echo "🎯 このファイルがSingle Source of Truthになります"
  echo "   変更は kong.yaml を編集し、'deck gateway sync' で適用してください"
fi
