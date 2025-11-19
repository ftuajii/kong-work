#!/bin/bash

set -e

echo "📄 Kong Konnect Dev Portal - API Spec公開"
echo "=========================================="

# 自動作成モードの表示
if [ "$VERSION_ID" = "auto-create-or-select" ] || [ "${AUTO_SELECT_VERSION:-false}" = "true" ]; then
  echo "🤖 自動作成/選択モード: 有効"
fi

echo ""

# ========================================
# 共通関数定義
# ========================================

# 環境変数チェック
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

# yqコマンド検索
find_yq_command() {
  if command -v yq &> /dev/null; then
    echo "yq"
  elif [ -f "/opt/homebrew/bin/yq" ]; then
    echo "/opt/homebrew/bin/yq"
  elif [ -f "/usr/local/bin/yq" ]; then
    echo "/usr/local/bin/yq"
  else
    echo ""
  fi
}

# YAML→JSON変換
convert_yaml_to_json() {
  local spec_file=$1
  
  if [[ "$spec_file" == *.yaml ]] || [[ "$spec_file" == *.yml ]]; then
    echo "🔄 YAML to JSON変換中..." >&2
    
    local yq_cmd=$(find_yq_command)
    if [ -z "$yq_cmd" ]; then
      echo "❌ yqコマンドが見つかりません" >&2
      echo "💡 インストール: brew install yq" >&2
      exit 1
    fi
    
    local json=$($yq_cmd -o=json '.' "$spec_file" | jq -c '.')
    if [ -z "$json" ]; then
      echo "❌ YAML to JSON変換に失敗" >&2
      exit 1
    fi
    echo "$json"
  else
    # JSONの場合はそのまま使用
    cat "$spec_file" | jq -c '.'
  fi
}

# Current Version更新
update_current_version() {
  local api_id=$1
  local version=$2
  
  echo ""
  echo "🔄 APIのCurrent Versionを更新中..."
  
  local response=$(curl -s -w "\n%{http_code}" \
    -X PATCH \
    "${KONNECT_API_ENDPOINT}/v3/apis/${api_id}" \
    -H "Authorization: Bearer ${KONNECT_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"version\": \"${version}\"}")
  
  local status=$(echo "$response" | tail -n 1)
  local body=$(echo "$response" | sed '$d')
  
  if [ "$status" -ge 200 ] && [ "$status" -lt 300 ]; then
    local updated=$(echo "$body" | jq -r '.version')
    echo "✅ Current Versionを '$updated' に更新しました"
    echo "   Dev Portalにも反映されます"
  else
    echo "⚠️  Current Version更新に失敗 (HTTP $status)"
    echo "📋 エラー詳細:"
    echo "$body" | jq '.' || echo "$body"
  fi
}

# Version公開
publish_version() {
  local api_id=$1
  local version_id=$2
  
  echo ""
  echo "📢 Versionを公開状態に設定中..."
  
  local payload=$(jq -n '{status: "published"}')
  local response=$(curl -s -w "\n%{http_code}" \
    -X PATCH \
    "${KONNECT_API_ENDPOINT}/v3/apis/${api_id}/versions/${version_id}" \
    -H "Authorization: Bearer ${KONNECT_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$payload")
  
  local status=$(echo "$response" | tail -n 1)
  local body=$(echo "$response" | sed '$d')
  
  if [ "$status" -ge 200 ] && [ "$status" -lt 300 ]; then
    echo "✅ Version公開成功 (HTTP $status)"
  else
    echo "⚠️  Version公開失敗 (HTTP $status)"
    echo "📋 エラー詳細:"
    echo "$body" | jq '.' || echo "$body"
    echo ""
    echo "ℹ️  Versionの作成は成功しましたが、公開設定に失敗しました"
    echo "   Konnect UIから手動で公開してください"
  fi
}

# 完了メッセージ表示
show_completion_message() {
  echo ""
  echo "=============================="
  echo "✅ API Spec公開処理が完了しました"
  echo "=============================="
  echo ""
  echo "📌 次のステップ:"
  echo "   1. Konnect UI (https://cloud.konghq.com/) にアクセス"
  echo "   2. APIs → 対象のAPI → Versions"
  echo "   3. Specificationsタブで登録されたSpecを確認"
  echo "   4. Dev Portalで公開されたAPI仕様を確認"
  echo ""
  echo "💡 今後の使用方法:"
  echo "   - 同じAPIに更新: 同じ環境変数で再実行"
  echo "   - 新しいAPI作成: export API_PRODUCT_ID='new-api-name'"
  echo "   - 自動Version選択: AUTO_SELECT_VERSION=true"
  echo ""
}

# ========================================
# メイン処理開始
# ========================================

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

# API ID (v3ではAPI Product IDではなくAPI IDを使用)
# 自動作成モードでは、API名またはAPI IDを指定可能
if ! check_env_var "API_PRODUCT_ID"; then
  echo ""
  echo "📝 API IDまたはAPI名の指定方法:"
  echo "   1. 既存APIのID: export API_PRODUCT_ID='existing-api-id'"
  echo "   2. 既存APIの名前: export API_PRODUCT_ID='existing-api-name'"
  echo "   3. 新規API名: export API_PRODUCT_ID='new-api-name'"
  echo ""
  echo "   ※ 指定されたIDまたは名前のAPIが存在しない場合、"
  echo "     自動的に新しいAPIが作成されます"
  echo ""
  echo "💡 またはKonnect UIから確認："
  echo "   1. Konnect UI → APIs"
  echo "   2. 対象のAPIを選択"
  echo "   3. URLまたは詳細画面からIDを確認"
  echo ""
  exit 1
fi

# API Version ID
# 自動作成モードでは、Version IDは必須ではない
if ! check_env_var "VERSION_ID"; then
  echo ""
  echo "📝 Version IDの指定方法（オプション）:"
  echo "   1. 既存Version: export VERSION_ID='existing-version-id'"
  echo "   2. 自動選択: AUTO_SELECT_VERSION=true"
  echo "   3. 新規作成: VERSION_IDを指定せずに実行"
  echo ""
  echo "   ※ VERSION_IDが指定されていない場合："
  echo "     - 既存Versionがあれば一覧を表示"
  echo "     - 既存Versionがなければ自動作成"
  echo ""
  echo "💡 またはKonnect UIから確認："
  echo "   1. APIs → 対象のAPI → Versions"
  echo "   2. 対象のVersionを選択してIDを確認"
  echo ""
  
  # VERSION_IDが未設定の場合、仮の値を設定（後で自動作成または選択）
  VERSION_ID="auto-create-or-select"
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

# ========================================
# Step 1: OpenAPI Specを読み込み
# ========================================
echo "📄 Step 1/3: API Specを読み込み中..."

SPEC_CONTENT=$(cat "$SPEC_FILE")
if [ -z "$SPEC_CONTENT" ]; then
  echo "❌ API Spec読み込みに失敗しました"
  exit 1
fi

# バージョン情報を抽出（1回のみ）
SPEC_VERSION=$(echo "$SPEC_CONTENT" | grep -E '^[[:space:]]*version[[:space:]]*:' | sed 's/.*:[[:space:]]*//' | tr -d '"' | tr -d "'" || echo "1.0.0")

echo "✅ API Spec読み込み完了"
echo "📋 検出されたAPI仕様バージョン: $SPEC_VERSION"
echo ""

# ========================================
# Step 2: APIの確認/作成
# ========================================
# ========================================
# Step 2: APIの確認/作成
# ========================================
echo "� Step 2/4: APIを確認中..."

AVAILABLE_APIS=$(curl -s \
  -X GET \
  "${KONNECT_API_ENDPOINT}/v3/apis" \
  -H "Authorization: Bearer ${KONNECT_TOKEN}")

# 指定されたAPI IDが存在するかチェック
API_EXISTS=$(echo "$AVAILABLE_APIS" | jq -r --arg id "$API_PRODUCT_ID" '.data[]? | select(.id == $id) | .id' 2>/dev/null)

if [ -z "$API_EXISTS" ]; then
  # API名から検索を試行
  API_BY_NAME=$(echo "$AVAILABLE_APIS" | jq -r --arg name "$API_PRODUCT_ID" '.data[]? | select(.name == $name) | .id' 2>/dev/null)
  
  if [ -n "$API_BY_NAME" ]; then
    echo "✅ API名 '${API_PRODUCT_ID}' でAPIが見つかりました"
    API_PRODUCT_ID="$API_BY_NAME"
  else
    echo "🆕 新しいAPIを作成します..."
    
    # API名を生成
    if [[ "$API_PRODUCT_ID" =~ ^[a-f0-9-]{36}$ ]]; then
      API_NAME=$(basename "$SPEC_FILE" .yaml | sed 's/[^a-zA-Z0-9-]/-/g')
      [ -z "$API_NAME" ] || [ "$API_NAME" = "openapi" ] && API_NAME="bookinfo-api"
    else
      API_NAME="$API_PRODUCT_ID"
    fi
    
    echo "📝 API名: $API_NAME"
    
    CREATE_API_PAYLOAD=$(jq -n \
      --arg name "$API_NAME" \
      --arg description "Auto-created API for $SPEC_FILE" \
      '{name: $name, description: $description}')
    
    CREATE_API_RESPONSE=$(curl -s -w "\n%{http_code}" \
      -X POST \
      "${KONNECT_API_ENDPOINT}/v3/apis" \
      -H "Authorization: Bearer ${KONNECT_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "$CREATE_API_PAYLOAD")
    
    CREATE_API_STATUS=$(echo "$CREATE_API_RESPONSE" | tail -n 1)
    CREATE_API_BODY=$(echo "$CREATE_API_RESPONSE" | sed '$d')
    
    if [ "$CREATE_API_STATUS" -ge 200 ] && [ "$CREATE_API_STATUS" -lt 300 ]; then
      API_PRODUCT_ID=$(echo "$CREATE_API_BODY" | jq -r '.id')
      echo "✅ API作成成功 (HTTP $CREATE_API_STATUS)"
      echo "🆔 新しいAPI ID: $API_PRODUCT_ID"
    else
      echo "❌ API作成失敗 (HTTP $CREATE_API_STATUS)"
      echo "📋 エラー詳細:"
      echo "$CREATE_API_BODY" | jq '.' || echo "$CREATE_API_BODY"
      exit 1
    fi
  fi
fi

echo "✅ API ID '${API_PRODUCT_ID}' が確認されました"
echo ""

# ========================================
# Step 3: Versionの確認/作成
# ========================================
echo "🔍 Step 3/4: Versionを確認中..."

AVAILABLE_VERSIONS=$(curl -s \
  -X GET \
  "${KONNECT_API_ENDPOINT}/v3/apis/${API_PRODUCT_ID}/versions" \
  -H "Authorization: Bearer ${KONNECT_TOKEN}")

VERSION_COUNT=$(echo "$AVAILABLE_VERSIONS" | jq -r '.data | length // 0' 2>/dev/null || echo "0")

# 同じバージョン名のVersionが存在するかチェック
MATCHING_VERSION_ID=$(echo "$AVAILABLE_VERSIONS" | jq -r --arg version "$SPEC_VERSION" '.data[]? | select(.version == $version) | .id' | head -n 1)

if [ -n "$MATCHING_VERSION_ID" ]; then
  echo "✅ 既存のVersion '$SPEC_VERSION' (ID: $MATCHING_VERSION_ID) が見つかりました"
  echo "🔄 このVersionを更新します"
  VERSION_ID="$MATCHING_VERSION_ID"
  VERSION_CREATED=false
elif [ "${AUTO_SELECT_VERSION:-false}" = "true" ] && [ "$VERSION_COUNT" -gt 0 ]; then
  VERSION_ID=$(echo "$AVAILABLE_VERSIONS" | jq -r '.data[0].id')
  echo "🔄 最新のVersion ID '${VERSION_ID}' を自動選択しました"
  VERSION_CREATED=false
else
  echo "🆕 Version '$SPEC_VERSION' を作成します..."
  
  # JSON変換
  SPEC_JSON=$(convert_yaml_to_json "$SPEC_FILE")
  
  CREATE_VERSION_PAYLOAD=$(jq -n \
    --arg version "$SPEC_VERSION" \
    --arg content "$SPEC_JSON" \
    '{version: $version, spec: {content: $content}}')
  
  CREATE_VERSION_RESPONSE=$(curl -s -w "\n%{http_code}" \
    -X POST \
    "${KONNECT_API_ENDPOINT}/v3/apis/${API_PRODUCT_ID}/versions" \
    -H "Authorization: Bearer ${KONNECT_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$CREATE_VERSION_PAYLOAD")
  
  CREATE_VERSION_STATUS=$(echo "$CREATE_VERSION_RESPONSE" | tail -n 1)
  CREATE_VERSION_BODY=$(echo "$CREATE_VERSION_RESPONSE" | sed '$d')
  
  if [ "$CREATE_VERSION_STATUS" -ge 200 ] && [ "$CREATE_VERSION_STATUS" -lt 300 ]; then
    VERSION_ID=$(echo "$CREATE_VERSION_BODY" | jq -r '.id')
    echo "✅ Version作成成功 (HTTP $CREATE_VERSION_STATUS)"
    echo "🆔 新しいVersion ID: $VERSION_ID"
    VERSION_CREATED=true
    
    # 公開設定
    [ "${PUBLISH_VERSION:-false}" = "true" ] && publish_version "$API_PRODUCT_ID" "$VERSION_ID"
    
    # Current Version更新
    update_current_version "$API_PRODUCT_ID" "$SPEC_VERSION"
    
    echo ""
    echo "✅ Version作成と仕様書登録が完了しました"
    show_completion_message
    exit 0
  else
    echo "❌ Version作成失敗 (HTTP $CREATE_VERSION_STATUS)"
    echo "📋 エラー詳細:"
    echo "$CREATE_VERSION_BODY" | jq '.' || echo "$CREATE_VERSION_BODY"
    exit 1
  fi
fi

echo ""

# ========================================
# Step 4: 既存Versionに仕様書を更新
# ========================================
echo "📤 Step 4/4: Versionに仕様書を登録/更新中..."

# JSON変換（まだ実行されていない場合）
[ -z "$SPEC_JSON" ] && SPEC_JSON=$(convert_yaml_to_json "$SPEC_FILE")

PAYLOAD=$(jq -n \
  --arg version "$SPEC_VERSION" \
  --arg content "$SPEC_JSON" \
  '{version: $version, spec: {content: $content}}')

RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X PATCH \
  "${KONNECT_API_ENDPOINT}/v3/apis/${API_PRODUCT_ID}/versions/${VERSION_ID}" \
  -H "Authorization: Bearer ${KONNECT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")

HTTP_STATUS=$(echo "$RESPONSE" | tail -n 1)
HTTP_BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_STATUS" -ge 200 ] && [ "$HTTP_STATUS" -lt 300 ]; then
  echo "✅ API仕様書登録成功 (HTTP $HTTP_STATUS)"
  
  # 公開設定
  [ "${PUBLISH_VERSION:-false}" = "true" ] && publish_version "$API_PRODUCT_ID" "$VERSION_ID"
  
  # Current Version更新
  update_current_version "$API_PRODUCT_ID" "$SPEC_VERSION"
  
  show_completion_message
else
  echo "❌ API仕様書登録失敗 (HTTP $HTTP_STATUS)"
  echo "📋 エラー詳細:"
  echo "$HTTP_BODY" | jq '.' || echo "$HTTP_BODY"
  exit 1
fi
