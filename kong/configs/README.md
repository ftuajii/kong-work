# Kong Application Configurations

このディレクトリには、Kong アプリケーションの設定ファイルを格納します。

## 想定される設定

### Routes (ルート設定)

- `routes/` - Kong Gateway のルート定義
- HTTP リクエストのルーティングルール

### Services (サービス設定)

- `services/` - バックエンドサービスの定義
- アップストリームサービスへの接続設定

### Plugins (プラグイン設定)

- `plugins/` - Kong プラグインの設定
- 認証、レート制限、ログ記録などの機能

### Upstreams (アップストリーム設定)

- `upstreams/` - ロードバランシング設定
- バックエンドターゲットのグループ化

## 設定方法

Kong Konnect を使用する場合、これらの設定は Konnect Control Plane (CP)から管理されます。

ローカルでの設定適用には以下の方法があります:

1. **Konnect UI** (推奨)

   - Konnect CP の Web UI から設定を管理

2. **decK** (Configuration as Code)

   ```bash
   # deck.yamlファイルを使用した設定同期
   deck sync --konnect-token <your-token>
   ```

3. **Kong Admin API**
   ```bash
   # Admin APIを使用した設定 (CPモードでは非推奨)
   # Data Planeのみのモードでは使用不可
   ```

## 注意事項

- このプロジェクトは Konnect CP 接続用 Data Plane として構成されています
- 設定は Konnect CP で管理することが推奨されます
- このディレクトリは将来的な設定ファイルのバージョン管理用です
