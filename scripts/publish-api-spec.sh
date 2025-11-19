#!/bin/bash

set -e

echo "📄 Kong Konnect Dev Portal - API Spec公開"
echo "=========================================="

# 自動作成モードの表示
if [ "$VERSION_ID" = "auto-create-or-select" ] || [ "${AUTO_SELECT_VERSION:-false}" = "true" ]; then
  echo "🤖 自動作成/選択モード: 有効"
fi

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

# Step 1: OpenAPI Specを読み込み
echo "📄 Step 1/3: API Specを読み込み中..."

# v3では仕様書を直接JSON/YAMLとして扱う
SPEC_CONTENT=$(cat "$SPEC_FILE")

if [ -z "$SPEC_CONTENT" ]; then
  echo "❌ API Spec読み込みに失敗しました"
  exit 1
fi

echo "✅ API Spec読み込み完了"
echo ""

# Step 2: 既存のAPI Versionを確認
echo "🔍 Step 2/3: 既存のAPI Versionを確認中..."

# まず、利用可能なAPIのリストを取得して確認
echo "📋 利用可能なAPIを確認中..."
AVAILABLE_APIS=$(curl -s \
  -X GET \
  "${KONNECT_API_ENDPOINT}/v3/apis" \
  -H "Authorization: Bearer ${KONNECT_TOKEN}")

echo "📋 利用可能なAPIリスト:"
echo "$AVAILABLE_APIS" | jq '.' || echo "$AVAILABLE_APIS"
echo ""

# 指定されたAPI IDが存在するかチェック
API_EXISTS=$(echo "$AVAILABLE_APIS" | jq -r --arg id "$API_PRODUCT_ID" '.data[]? | select(.id == $id) | .id' 2>/dev/null)

if [ -z "$API_EXISTS" ]; then
  echo "⚠️  指定されたAPI ID '${API_PRODUCT_ID}' が見つかりません"
  
  # API名から検索を試行
  API_BY_NAME=$(echo "$AVAILABLE_APIS" | jq -r --arg name "$API_PRODUCT_ID" '.data[]? | select(.name == $name) | .id' 2>/dev/null)
  
  if [ -n "$API_BY_NAME" ]; then
    echo "✅ API名 '${API_PRODUCT_ID}' でAPIが見つかりました"
    API_PRODUCT_ID="$API_BY_NAME"
    echo "🔄 API IDを '${API_PRODUCT_ID}' に更新しました"
  else
    echo "🆕 新しいAPIを作成します..."
    
    # 新しいAPI名を生成（API_PRODUCT_IDまたはSpecファイル名から）
    if [[ "$API_PRODUCT_ID" =~ ^[a-f0-9-]{36}$ ]]; then
      # UUIDの場合は、Specファイル名からAPI名を生成
      API_NAME=$(basename "$SPEC_FILE" .yaml | sed 's/[^a-zA-Z0-9-]/-/g')
      if [ -z "$API_NAME" ] || [ "$API_NAME" = "openapi" ]; then
        API_NAME="bookinfo-api"
      fi
    else
      # UUID以外の場合は、API_PRODUCT_IDをAPI名として使用
      API_NAME="$API_PRODUCT_ID"
    fi
    
    echo "📝 API名: $API_NAME"
    
    # 新しいAPIを作成
    CREATE_API_PAYLOAD=$(jq -n \
      --arg name "$API_NAME" \
      --arg description "Auto-created API for $SPEC_FILE" \
      '{
        name: $name,
        description: $description
      }')
    
    echo "🔨 APIを作成中..."
    CREATE_API_RESPONSE=$(curl -s -w "\n%{http_code}" \
      -X POST \
      "${KONNECT_API_ENDPOINT}/v3/apis" \
      -H "Authorization: Bearer ${KONNECT_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "$CREATE_API_PAYLOAD")
    
    CREATE_API_STATUS=$(echo "$CREATE_API_RESPONSE" | tail -n 1)
    CREATE_API_BODY=$(echo "$CREATE_API_RESPONSE" | sed '$d')
    
    if [ "$CREATE_API_STATUS" -ge 200 ] && [ "$CREATE_API_STATUS" -lt 300 ]; then
      NEW_API_ID=$(echo "$CREATE_API_BODY" | jq -r '.id')
      echo "✅ API作成成功 (HTTP $CREATE_API_STATUS)"
      echo "🆔 新しいAPI ID: $NEW_API_ID"
      API_PRODUCT_ID="$NEW_API_ID"
    else
      echo "❌ API作成失敗 (HTTP $CREATE_API_STATUS)"
      echo "📋 エラー詳細:"
      echo "$CREATE_API_BODY" | jq '.' || echo "$CREATE_API_BODY"
      echo ""
      echo "💡 手動でAPIを作成するか、利用可能なAPI IDを指定してください:"
      echo "$AVAILABLE_APIS" | jq -r '.data[]? | "- ID: \(.id), Name: \(.name)"' || echo "APIの取得に失敗しました"
      exit 1
    fi
  fi
fi

echo "✅ API ID '${API_PRODUCT_ID}' が確認されました"
echo ""

# v3では、API Versionを直接確認
EXISTING_VERSION=$(curl -s \
  -X GET \
  "${KONNECT_API_ENDPOINT}/v3/apis/${API_PRODUCT_ID}/versions/${VERSION_ID}" \
  -H "Authorization: Bearer ${KONNECT_TOKEN}")

echo "📋 API Version情報:"
echo "$EXISTING_VERSION" | jq '.' || echo "$EXISTING_VERSION"
echo ""

# 既存の仕様書があるかチェック
EXISTING_SPEC=$(echo "$EXISTING_VERSION" | jq -r '.spec.content // empty' 2>/dev/null)

# Version IDが正しいかもチェック
VERSION_ERROR=$(echo "$EXISTING_VERSION" | jq -r '.status // empty' 2>/dev/null)
if [ "$VERSION_ERROR" = "404" ]; then
  echo "⚠️  指定されたVersion ID '${VERSION_ID}' が見つかりません"
  
  echo "📝 利用可能なVersionを確認中..."
  AVAILABLE_VERSIONS=$(curl -s \
    -X GET \
    "${KONNECT_API_ENDPOINT}/v3/apis/${API_PRODUCT_ID}/versions" \
    -H "Authorization: Bearer ${KONNECT_TOKEN}")
  
  echo "📋 利用可能なVersionリスト:"
  echo "$AVAILABLE_VERSIONS" | jq -r '.data[]? | "- ID: \(.id), Version: \(.version), Status: \(.status)"' || echo "Versionの取得に失敗しました"
  
  # バージョン数をチェック
  VERSION_COUNT=$(echo "$AVAILABLE_VERSIONS" | jq -r '.data | length // 0' 2>/dev/null || echo "0")
  
  if [ "$VERSION_COUNT" -eq 0 ]; then
    echo ""
    echo "🆕 Versionが存在しないため、新しいVersionを作成します..."
    
    # OpenAPI仕様からバージョンを取得
    SPEC_VERSION=$(echo "$SPEC_CONTENT" | grep -E '^[[:space:]]*version[[:space:]]*:' | sed 's/.*:[[:space:]]*//' | tr -d '"' | tr -d "'" || echo "1.0.0")
    echo "📋 検出されたAPI仕様バージョン: $SPEC_VERSION"
    
    # JSON形式に変換（YAMLの場合）
    if [[ "$SPEC_FILE" == *.yaml ]] || [[ "$SPEC_FILE" == *.yml ]]; then
      echo "🔄 YAML to JSON変換中..."
      
      # yqコマンドでYAMLをJSONに変換
      YQ_CMD=""
      if command -v yq &> /dev/null; then
        YQ_CMD="yq"
      elif [ -f "/opt/homebrew/bin/yq" ]; then
        YQ_CMD="/opt/homebrew/bin/yq"
      elif [ -f "/usr/local/bin/yq" ]; then
        YQ_CMD="/usr/local/bin/yq"
      else
        echo "❌ yqコマンドが見つかりません"
        echo "💡 インストール: brew install yq"
        exit 1
      fi
      
      SPEC_JSON=$($YQ_CMD -o=json '.' "$SPEC_FILE" | jq -c '.')
      
      if [ -z "$SPEC_JSON" ]; then
        echo "❌ YAML to JSON変換に失敗"
        exit 1
      fi
    else
      # JSONの場合はそのまま使用
      SPEC_JSON=$(echo "$SPEC_CONTENT" | jq -c '.')
    fi
    
    # 新しいVersionを作成（specを含む）
    CREATE_VERSION_PAYLOAD=$(jq -n \
      --arg version "$SPEC_VERSION" \
      --arg content "$SPEC_JSON" \
      '{
        version: $version,
        spec: {
          content: $content
        }
      }')
    
    echo "🔨 Versionを作成中..."
    CREATE_VERSION_RESPONSE=$(curl -s -w "\n%{http_code}" \
      -X POST \
      "${KONNECT_API_ENDPOINT}/v3/apis/${API_PRODUCT_ID}/versions" \
      -H "Authorization: Bearer ${KONNECT_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "$CREATE_VERSION_PAYLOAD")
    
    CREATE_VERSION_STATUS=$(echo "$CREATE_VERSION_RESPONSE" | tail -n 1)
    CREATE_VERSION_BODY=$(echo "$CREATE_VERSION_RESPONSE" | sed '$d')
    
    if [ "$CREATE_VERSION_STATUS" -ge 200 ] && [ "$CREATE_VERSION_STATUS" -lt 300 ]; then
      NEW_VERSION_ID=$(echo "$CREATE_VERSION_BODY" | jq -r '.id')
      echo "✅ Version作成成功 (HTTP $CREATE_VERSION_STATUS)"
      echo "🆔 新しいVersion ID: $NEW_VERSION_ID"
      VERSION_ID="$NEW_VERSION_ID"
      
      # 公開状態の設定（必要な場合）
      if [ "${PUBLISH_VERSION:-false}" = "true" ]; then
        echo ""
        echo "📢 作成したVersionを公開状態に設定中..."
        
        PUBLISH_PAYLOAD=$(jq -n '{
          status: "published"
        }')
        
        PUBLISH_RESPONSE=$(curl -s -w "\n%{http_code}" \
          -X PATCH \
          "${KONNECT_API_ENDPOINT}/v3/apis/${API_PRODUCT_ID}/versions/${VERSION_ID}" \
          -H "Authorization: Bearer ${KONNECT_TOKEN}" \
          -H "Content-Type: application/json" \
          -d "$PUBLISH_PAYLOAD")
        
        PUBLISH_STATUS=$(echo "$PUBLISH_RESPONSE" | tail -n 1)
        PUBLISH_BODY=$(echo "$PUBLISH_RESPONSE" | sed '$d')
        
        if [ "$PUBLISH_STATUS" -ge 200 ] && [ "$PUBLISH_STATUS" -lt 300 ]; then
          echo "✅ Version公開成功 (HTTP $PUBLISH_STATUS)"
        else
          echo "⚠️  Version公開失敗 (HTTP $PUBLISH_STATUS)"
          echo "📋 エラー詳細:"
          echo "$PUBLISH_BODY" | jq '.' || echo "$PUBLISH_BODY"
          echo ""
          echo "ℹ️  Versionの作成は成功しましたが、公開設定に失敗しました"
          echo "   Konnect UIから手動で公開してください"
        fi
      fi
      
      # Version作成時に仕様書も含まれているため、Step 3をスキップ
      echo ""
      echo "✅ API仕様書の登録と公開が完了しました（Version作成時に含まれています）"
      
      # Current Versionを新しく作成したバージョンに更新
      echo ""
      echo "🔄 APIのCurrent Versionを更新中..."
      UPDATE_CURRENT_RESPONSE=$(curl -s -w "\n%{http_code}" \
        -X PATCH \
        "${KONNECT_API_ENDPOINT}/v3/apis/${API_PRODUCT_ID}" \
        -H "Authorization: Bearer ${KONNECT_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"version\": \"${SPEC_VERSION}\"}")
      
      UPDATE_CURRENT_STATUS=$(echo "$UPDATE_CURRENT_RESPONSE" | tail -n 1)
      UPDATE_CURRENT_BODY=$(echo "$UPDATE_CURRENT_RESPONSE" | sed '$d')
      
      if [ "$UPDATE_CURRENT_STATUS" -ge 200 ] && [ "$UPDATE_CURRENT_STATUS" -lt 300 ]; then
        UPDATED_VERSION=$(echo "$UPDATE_CURRENT_BODY" | jq -r '.version')
        echo "✅ Current Versionを '$UPDATED_VERSION' に更新しました"
        echo "   Dev Portalにも反映されます"
      else
        echo "⚠️  Current Version更新に失敗 (HTTP $UPDATE_CURRENT_STATUS)"
        echo "📋 エラー詳細:"
        echo "$UPDATE_CURRENT_BODY" | jq '.' || echo "$UPDATE_CURRENT_BODY"
      fi
      
      # 最終メッセージを表示してスクリプト終了
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
      exit 0
    else
      echo "❌ Version作成失敗 (HTTP $CREATE_VERSION_STATUS)"
      echo "📋 エラー詳細:"
      echo "$CREATE_VERSION_BODY" | jq '.' || echo "$CREATE_VERSION_BODY"
      exit 1
    fi
  else
    # OpenAPI仕様からバージョンを取得
    SPEC_VERSION=$(echo "$SPEC_CONTENT" | grep -E '^[[:space:]]*version[[:space:]]*:' | sed 's/.*:[[:space:]]*//' | tr -d '"' | tr -d "'" || echo "1.0.0")
    echo ""
    echo "📋 検出されたAPI仕様バージョン: $SPEC_VERSION"
    
    # 同じバージョン名のVersionが存在するかチェック
    MATCHING_VERSION_ID=$(echo "$AVAILABLE_VERSIONS" | jq -r --arg version "$SPEC_VERSION" '.data[]? | select(.version == $version) | .id' | head -n 1)
    
    if [ -n "$MATCHING_VERSION_ID" ]; then
      echo "✅ 既存のVersion '$SPEC_VERSION' (ID: $MATCHING_VERSION_ID) が見つかりました"
      echo "🔄 このVersionを更新します"
      VERSION_ID="$MATCHING_VERSION_ID"
      
      # Current Versionを更新（既存バージョンを使用する場合）
      echo ""
      echo "🔄 APIのCurrent Versionを更新中..."
      UPDATE_CURRENT_RESPONSE=$(curl -s -w "\n%{http_code}" \
        -X PATCH \
        "${KONNECT_API_ENDPOINT}/v3/apis/${API_PRODUCT_ID}" \
        -H "Authorization: Bearer ${KONNECT_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"version\": \"${SPEC_VERSION}\"}")
      
      UPDATE_CURRENT_STATUS=$(echo "$UPDATE_CURRENT_RESPONSE" | tail -n 1)
      UPDATE_CURRENT_BODY=$(echo "$UPDATE_CURRENT_RESPONSE" | sed '$d')
      
      if [ "$UPDATE_CURRENT_STATUS" -ge 200 ] && [ "$UPDATE_CURRENT_STATUS" -lt 300 ]; then
        UPDATED_VERSION=$(echo "$UPDATE_CURRENT_BODY" | jq -r '.version')
        echo "✅ Current Versionを '$UPDATED_VERSION' に更新しました"
        echo "   Dev Portalにも反映されます"
      else
        echo "⚠️  Current Version更新に失敗 (HTTP $UPDATE_CURRENT_STATUS)"
        echo "📋 エラー詳細:"
        echo "$UPDATE_CURRENT_BODY" | jq '.' || echo "$UPDATE_CURRENT_BODY"
      fi
      
      # 選択されたVersionを再確認
      EXISTING_VERSION=$(curl -s \
        -X GET \
        "${KONNECT_API_ENDPOINT}/v3/apis/${API_PRODUCT_ID}/versions/${VERSION_ID}" \
        -H "Authorization: Bearer ${KONNECT_TOKEN}")
    elif [ "${AUTO_SELECT_VERSION:-false}" = "true" ]; then
      LATEST_VERSION_ID=$(echo "$AVAILABLE_VERSIONS" | jq -r '.data[0].id')
      echo ""
      echo "🔄 最新のVersion ID '${LATEST_VERSION_ID}' を自動選択しました"
      VERSION_ID="$LATEST_VERSION_ID"
      
      # 選択されたVersionを再確認
      EXISTING_VERSION=$(curl -s \
        -X GET \
        "${KONNECT_API_ENDPOINT}/v3/apis/${API_PRODUCT_ID}/versions/${VERSION_ID}" \
        -H "Authorization: Bearer ${KONNECT_TOKEN}")
    else
      echo ""
      echo "🆕 Version '$SPEC_VERSION' が存在しないため、新しいVersionを作成します..."
      
      # JSON形式に変換（YAMLの場合）
      if [[ "$SPEC_FILE" == *.yaml ]] || [[ "$SPEC_FILE" == *.yml ]]; then
        echo "🔄 YAML to JSON変換中..."
        
        # yqコマンドでYAMLをJSONに変換
        YQ_CMD=""
        if command -v yq &> /dev/null; then
          YQ_CMD="yq"
        elif [ -f "/opt/homebrew/bin/yq" ]; then
          YQ_CMD="/opt/homebrew/bin/yq"
        elif [ -f "/usr/local/bin/yq" ]; then
          YQ_CMD="/usr/local/bin/yq"
        else
          echo "❌ yqコマンドが見つかりません"
          echo "💡 インストール: brew install yq"
          exit 1
        fi
        
        SPEC_JSON=$($YQ_CMD -o=json '.' "$SPEC_FILE" | jq -c '.')
        
        if [ -z "$SPEC_JSON" ]; then
          echo "❌ YAML to JSON変換に失敗"
          exit 1
        fi
      else
        # JSONの場合はそのまま使用
        SPEC_JSON=$(echo "$SPEC_CONTENT" | jq -c '.')
      fi
      
      # 新しいVersionを作成（specを含む）
      CREATE_VERSION_PAYLOAD=$(jq -n \
        --arg version "$SPEC_VERSION" \
        --arg content "$SPEC_JSON" \
        '{
          version: $version,
          spec: {
            content: $content
          }
        }')
      
      echo "🔨 Versionを作成中..."
      CREATE_VERSION_RESPONSE=$(curl -s -w "\n%{http_code}" \
        -X POST \
        "${KONNECT_API_ENDPOINT}/v3/apis/${API_PRODUCT_ID}/versions" \
        -H "Authorization: Bearer ${KONNECT_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$CREATE_VERSION_PAYLOAD")
      
      CREATE_VERSION_STATUS=$(echo "$CREATE_VERSION_RESPONSE" | tail -n 1)
      CREATE_VERSION_BODY=$(echo "$CREATE_VERSION_RESPONSE" | sed '$d')
      
      if [ "$CREATE_VERSION_STATUS" -ge 200 ] && [ "$CREATE_VERSION_STATUS" -lt 300 ]; then
        NEW_VERSION_ID=$(echo "$CREATE_VERSION_BODY" | jq -r '.id')
        echo "✅ Version作成成功 (HTTP $CREATE_VERSION_STATUS)"
        echo "🆔 新しいVersion ID: $NEW_VERSION_ID"
        VERSION_ID="$NEW_VERSION_ID"
        
        # Version作成時に仕様書も含まれているため、Step 3をスキップ
        echo ""
        echo "✅ API仕様書の登録と公開が完了しました（Version作成時に含まれています）"
        
        # 最終メッセージを表示してスクリプト終了
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
        exit 0
      else
        echo "❌ Version作成失敗 (HTTP $CREATE_VERSION_STATUS)"
        echo "📋 エラー詳細:"
        echo "$CREATE_VERSION_BODY" | jq '.' || echo "$CREATE_VERSION_BODY"
        exit 1
      fi
    fi
  fi
fi

if [ -n "$EXISTING_SPEC" ]; then
  echo "⚠️  既存のAPI仕様書が見つかりました"
  
  if [ "${OVERWRITE_EXISTING:-true}" = "true" ]; then
    echo "🔄 既存のAPI仕様書を上書きします..."
  else
    echo "❌ 既存のAPI仕様書が存在します"
    echo ""
    echo "💡 既存の仕様書を上書きして更新するには:"
    echo "   OVERWRITE_EXISTING=true ./scripts/publish-api-spec.sh"
    echo ""
    echo "   または、Konnect UIから手動で確認してください:"
    echo "   1. APIs → 対象のAPI → Versions"
    echo "   2. 対象のVersionを選択してSpecificationを確認"
    exit 1
  fi
else
  echo "✅ 既存のAPI仕様書は見つかりませんでした"
fi

echo ""

# Step 3: API Versionに仕様書を登録/更新
# GitHub Actionsの例を参考に、正しいv3 API構造を使用
if [ "${PUBLISH_VERSION:-false}" = "true" ]; then
  echo "📤 Step 3/3: Konnect APIのVersionに仕様書を登録し、公開状態に設定中..."
else
  echo "📤 Step 3/3: Konnect APIのVersionに仕様書を登録中..."
fi

# JSON変換を行う（まだ実行されていない場合）
if [ -z "$SPEC_JSON" ]; then
  # OpenAPI仕様からバージョンを取得
  SPEC_VERSION=$(echo "$SPEC_CONTENT" | grep -E '^[[:space:]]*version[[:space:]]*:' | sed 's/.*:[[:space:]]*//' | tr -d '"' | tr -d "'" || echo "1.0.0")
  echo "📋 検出されたAPI仕様バージョン: $SPEC_VERSION"

  # JSON形式に変換（YAMLの場合）
  if [[ "$SPEC_FILE" == *.yaml ]] || [[ "$SPEC_FILE" == *.yml ]]; then
    echo "🔄 YAML to JSON変換中..."
    
    # yqコマンドでYAMLをJSONに変換
    YQ_CMD=""
    if command -v yq &> /dev/null; then
      YQ_CMD="yq"
    elif [ -f "/opt/homebrew/bin/yq" ]; then
      YQ_CMD="/opt/homebrew/bin/yq"
    elif [ -f "/usr/local/bin/yq" ]; then
      YQ_CMD="/usr/local/bin/yq"
    else
      echo "❌ yqコマンドが見つかりません"
      echo "💡 インストール: brew install yq"
      exit 1
    fi
    
    SPEC_JSON=$($YQ_CMD -o=json '.' "$SPEC_FILE" | jq -c '.')
    
    if [ -z "$SPEC_JSON" ]; then
      echo "❌ YAML to JSON変換に失敗"
      exit 1
    fi
  else
    # JSONの場合はそのまま使用
    SPEC_JSON=$(echo "$SPEC_CONTENT" | jq -c '.')
  fi
fi

# ペイロードを作成 (GitHub Actionsの例に基づく)
PAYLOAD=$(jq -n \
  --arg version "$SPEC_VERSION" \
  --arg content "$SPEC_JSON" \
  '{
    version: $version,
    spec: {
      content: $content
    }
  }')

echo "📤 API Versionに仕様書を登録/更新中..."

# API Versionを更新 (GitHub Actionsの例と同じ構造)
RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X PATCH \
  "${KONNECT_API_ENDPOINT}/v3/apis/${API_PRODUCT_ID}/versions/${VERSION_ID}" \
  -H "Authorization: Bearer ${KONNECT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")

# レスポンスとHTTPステータスコードを分離 (macOS互換)
HTTP_STATUS=$(echo "$RESPONSE" | tail -n 1)
HTTP_BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_STATUS" -ge 200 ] && [ "$HTTP_STATUS" -lt 300 ]; then
  echo "✅ API仕様書登録成功 (HTTP $HTTP_STATUS)"
  echo ""
  echo "📋 レスポンス詳細:"
  echo "$HTTP_BODY" | jq '.' || echo "$HTTP_BODY"
  
  # API Version IDを取得
  VERSION_ID_RESPONSE=$(echo "$HTTP_BODY" | jq -r '.id // empty')
  if [ -n "$VERSION_ID_RESPONSE" ]; then
    echo ""
    echo "🆔 API Version ID: $VERSION_ID_RESPONSE"
  fi
  
  # 公開状態の設定（必要な場合）
  if [ "${PUBLISH_VERSION:-false}" = "true" ]; then
    echo ""
    echo "📢 API Versionを公開状態に設定中..."
    
    PUBLISH_PAYLOAD=$(jq -n '{
      status: "published"
    }')
    
    PUBLISH_RESPONSE=$(curl -s -w "\n%{http_code}" \
      -X PATCH \
      "${KONNECT_API_ENDPOINT}/v3/apis/${API_PRODUCT_ID}/versions/${VERSION_ID}" \
      -H "Authorization: Bearer ${KONNECT_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "$PUBLISH_PAYLOAD")
    
    PUBLISH_STATUS=$(echo "$PUBLISH_RESPONSE" | tail -n 1)
    PUBLISH_BODY=$(echo "$PUBLISH_RESPONSE" | sed '$d')
    
    if [ "$PUBLISH_STATUS" -ge 200 ] && [ "$PUBLISH_STATUS" -lt 300 ]; then
      echo "✅ Version公開成功 (HTTP $PUBLISH_STATUS)"
    else
      echo "⚠️  Version公開失敗 (HTTP $PUBLISH_STATUS)"
      echo "📋 エラー詳細:"
      echo "$PUBLISH_BODY" | jq '.' || echo "$PUBLISH_BODY"
      echo ""
      echo "ℹ️  API仕様書の登録は成功しましたが、公開設定に失敗しました"
      echo "   Konnect UIから手動で公開してください"
    fi
  fi
else
  echo "❌ API仕様書登録失敗 (HTTP $HTTP_STATUS)"
  echo ""
  echo "📋 エラー詳細:"
  echo "$HTTP_BODY" | jq '.' || echo "$HTTP_BODY"
  exit 1
fi

echo ""

# 処理完了
if [ "${PUBLISH_VERSION:-false}" = "true" ]; then
  echo "✅ 仕様書登録と公開が同時に完了しました"
else
  echo "✅ 仕様書登録が完了しました"
  echo ""
  echo "💡 API Versionを公開するには、以下のコマンドを実行してください:"
  echo "   PUBLISH_VERSION=true ./scripts/publish-api-spec.sh"
  echo ""
  echo "   または、Konnect UIから手動で公開してください:"
  echo "   1. APIs → 対象のAPI → Versionsタブ"
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
echo "   2. APIs → 対象のAPI → Versions"
echo "   3. Specificationsタブで登録されたSpecを確認"
echo "   4. Dev Portalで公開されたAPI仕様を確認"
echo ""
echo "💡 今後の使用方法:"
echo "   - 同じAPIに更新: 同じ環境変数で再実行"
echo "   - 新しいAPI作成: export API_PRODUCT_ID='new-api-name'"
echo "   - 自動Version選択: AUTO_SELECT_VERSION=true"
echo ""
