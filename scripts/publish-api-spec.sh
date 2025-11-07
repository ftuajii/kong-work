#!/bin/bash

set -e

echo "📄 Kong Konnect Dev Portal - API Spec公開"
echo "=========================================="
echo ""

# 必要な環境変数のチェック
check_env_var() {
  local var_name=$1
  local var_value=${!var_name}
  
  if [ -z "$var_value" ]; then
    echo "❌ $var_name 環境変数が設定されていません"
    return 1
  else
    echo "✅ $var_name が設定されています"
    return 0
  fi
}

# Konnect Personal Access Token
if ! check_env_var "KONNECT_TOKEN"; then
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

# API Product ID
if ! check_env_var "API_PRODUCT_ID"; then
  echo ""
  echo "📝 API Product IDの取得方法:"
  echo "   1. Konnect UI → API Products"
  echo "   2. 対象のAPI Productを選択"
  echo "   3. URLまたは詳細画面からIDを確認"
  echo "   4. 以下のコマンドで設定:"
  echo "      export API_PRODUCT_ID='your-product-id-here'"
  echo ""
  exit 1
fi

# API Product Version ID
if ! check_env_var "VERSION_ID"; then
  echo ""
  echo "📝 API Product Version IDの取得方法:"
  echo "   1. Konnect UI → API Products → 対象のProduct"
  echo "   2. Versionsタブから対象のVersionを選択"
  echo "   3. URLまたは詳細画面からVersion IDを確認"
  echo "   4. 以下のコマンドで設定:"
  echo "      export VERSION_ID='your-version-id-here'"
  echo ""
  exit 1
fi

echo ""

# Konnect API Endpoint (デフォルトはUS region)
KONNECT_API_ENDPOINT="${KONNECT_API_ENDPOINT:-https://us.api.konghq.com}"
echo "🌐 Konnect API Endpoint: $KONNECT_API_ENDPOINT"

# OpenAPI Specファイルのパス
SPEC_FILE="${SPEC_FILE:-kong/specs/openapi.yaml}"

if [ ! -f "$SPEC_FILE" ]; then
  echo "❌ API Specファイルが見つかりません: $SPEC_FILE"
  exit 1
fi

echo "📄 API Specファイル: $SPEC_FILE"
echo ""

# Step 1: OpenAPI SpecをBase64エンコード
echo "🔐 Step 1/4: API SpecをBase64エンコード中..."

# macOSとLinuxでbase64コマンドのオプションが異なるため、両方に対応
if [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS
  SPEC_CONTENT=$(base64 -i "$SPEC_FILE")
else
  # Linux (GitHub Actions)
  SPEC_CONTENT=$(base64 -w 0 "$SPEC_FILE")
fi

if [ -z "$SPEC_CONTENT" ]; then
  echo "❌ Base64エンコードに失敗しました"
  exit 1
fi

echo "✅ Base64エンコード完了"
echo ""

# Step 2: 既存のSpecificationを確認
echo "🔍 Step 2/4: 既存のSpecificationを確認中..."

EXISTING_SPECS=$(curl -s \
  -X GET \
  "${KONNECT_API_ENDPOINT}/v2/api-products/${API_PRODUCT_ID}/product-versions/${VERSION_ID}/specifications" \
  -H "Authorization: Bearer ${KONNECT_TOKEN}")

EXISTING_SPEC_ID=$(echo "$EXISTING_SPECS" | jq -r '.data[0].id // empty')

if [ -n "$EXISTING_SPEC_ID" ]; then
  echo "⚠️  既存のSpecificationが見つかりました (ID: $EXISTING_SPEC_ID)"
  
  if [ "${DELETE_EXISTING:-true}" = "true" ]; then
    echo "🗑️  既存のSpecificationを削除中..."
    
    DELETE_RESPONSE=$(curl -s -w "\n%{http_code}" \
      -X DELETE \
      "${KONNECT_API_ENDPOINT}/v2/api-products/${API_PRODUCT_ID}/product-versions/${VERSION_ID}/specifications/${EXISTING_SPEC_ID}" \
      -H "Authorization: Bearer ${KONNECT_TOKEN}")
    
    DELETE_STATUS=$(echo "$DELETE_RESPONSE" | tail -n 1)
    
    if [ "$DELETE_STATUS" -eq 204 ] || [ "$DELETE_STATUS" -eq 200 ]; then
      echo "✅ 既存のSpecification削除成功"
    else
      echo "❌ 既存のSpecification削除失敗 (HTTP $DELETE_STATUS)"
      DELETE_BODY=$(echo "$DELETE_RESPONSE" | sed '$d')
      echo "$DELETE_BODY" | jq '.' || echo "$DELETE_BODY"
      exit 1
    fi
  else
    echo "❌ 既存のSpecificationが存在します"
    echo ""
    echo "💡 既存のSpecificationを削除して再登録するには:"
    echo "   DELETE_EXISTING=true ./scripts/publish-api-spec.sh"
    echo ""
    echo "   または、Konnect UIから手動で削除してください:"
    echo "   1. API Products → 対象のProduct → Product Versions"
    echo "   2. Specificationsタブ → 既存のSpecを削除"
    exit 1
  fi
else
  echo "✅ 既存のSpecificationは見つかりませんでした"
fi

echo ""

# Step 3: API Specificationを登録
echo "📤 Step 3/4: Konnect APIにSpecificationを登録中..."

# Specファイル名を取得 (拡張子付き)
SPEC_NAME=$(basename "$SPEC_FILE")

# JSONペイロードを作成
PAYLOAD=$(jq -n \
  --arg name "$SPEC_NAME" \
  --arg content "$SPEC_CONTENT" \
  '{
    name: $name,
    content: $content
  }')

# API Specificationを登録
RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X POST \
  "${KONNECT_API_ENDPOINT}/v2/api-products/${API_PRODUCT_ID}/product-versions/${VERSION_ID}/specifications" \
  -H "Authorization: Bearer ${KONNECT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")

# レスポンスとHTTPステータスコードを分離 (macOS互換)
HTTP_STATUS=$(echo "$RESPONSE" | tail -n 1)
HTTP_BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_STATUS" -ge 200 ] && [ "$HTTP_STATUS" -lt 300 ]; then
  echo "✅ Specification登録成功 (HTTP $HTTP_STATUS)"
  echo ""
  echo "📋 レスポンス詳細:"
  echo "$HTTP_BODY" | jq '.'
  
  # Specification IDを取得
  SPEC_ID=$(echo "$HTTP_BODY" | jq -r '.id // empty')
  if [ -n "$SPEC_ID" ]; then
    echo ""
    echo "🆔 Specification ID: $SPEC_ID"
  fi
else
  echo "❌ Specification登録失敗 (HTTP $HTTP_STATUS)"
  echo ""
  echo "📋 エラー詳細:"
  echo "$HTTP_BODY" | jq '.' || echo "$HTTP_BODY"
  exit 1
fi

echo ""

# Step 4: API Product Versionを公開状態に更新 (オプション)
if [ "${PUBLISH_VERSION:-false}" = "true" ]; then
  echo "🚀 Step 4/4: API Product Versionを公開状態に更新中..."
  
  PUBLISH_PAYLOAD=$(jq -n '{
    publish_status: "published"
  }')
  
  PUBLISH_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X PATCH \
    "${KONNECT_API_ENDPOINT}/v2/api-products/${API_PRODUCT_ID}/product-versions/${VERSION_ID}" \
    -H "Authorization: Bearer ${KONNECT_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$PUBLISH_PAYLOAD")
  
  # レスポンスとHTTPステータスコードを分離 (macOS互換)
  PUBLISH_STATUS=$(echo "$PUBLISH_RESPONSE" | tail -n 1)
  PUBLISH_BODY=$(echo "$PUBLISH_RESPONSE" | sed '$d')
  
  if [ "$PUBLISH_STATUS" -ge 200 ] && [ "$PUBLISH_STATUS" -lt 300 ]; then
    echo "✅ Version公開成功 (HTTP $PUBLISH_STATUS)"
    echo ""
    echo "📋 レスポンス詳細:"
    echo "$PUBLISH_BODY" | jq '.'
  else
    echo "⚠️  Version公開失敗 (HTTP $PUBLISH_STATUS)"
    echo ""
    echo "📋 エラー詳細:"
    echo "$PUBLISH_BODY" | jq '.' || echo "$PUBLISH_BODY"
    echo ""
    echo "ℹ️  Specificationの登録は成功しましたが、Versionの公開に失敗しました"
    echo "   Konnect UIから手動で公開してください"
  fi
else
  echo "ℹ️  Step 4/4: Version公開はスキップされました"
  echo ""
  echo "💡 API Product Versionを公開するには、以下のコマンドを実行してください:"
  echo "   PUBLISH_VERSION=true ./scripts/publish-api-spec.sh"
  echo ""
  echo "   または、Konnect UIから手動で公開してください:"
  echo "   1. API Products → 対象のProduct → Versionsタブ"
  echo "   2. 対象のVersionを選択"
  echo "   3. 'Publish' ボタンをクリック"
fi

echo ""
echo "=============================="
echo "✅ API Spec公開処理が完了しました"
echo "=============================="
echo ""
echo "📌 次のステップ:"
echo "   1. Konnect UI (https://cloud.konghq.com/) にアクセス"
echo "   2. API Products → 対象のProduct → Product Versions"
echo "   3. Specificationsタブで登録されたSpecを確認"
echo "   4. Dev Portalで公開されたAPI仕様を確認"
echo ""
