#!/bin/bash

set -e  # エラーが発生したら即座に終了

# スクリプトのディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🔄 Kong データプレーンを再デプロイします..."

# 1. Kong停止
"$SCRIPT_DIR/stop-kong.sh"

# 2. Kong起動
"$SCRIPT_DIR/start-kong.sh"

echo ""
echo "✅ 再デプロイ完了!"
