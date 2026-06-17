# recolle

ライブ・映画・本などの体験を記録する Flutter アプリです。チケット画像・セットリスト・MC メモ・感想などをまとめて残せるデータモデルを中心に、Supabase 認証と連携した構成になっています。アプリ表示名（`MaterialApp` の `title`）は **recolle** です。

## 技術スタック

| 領域 | 利用パッケージ |
|------|----------------|
| ルーティング | [go_router](https://pub.dev/packages/go_router)（タブは `StatefulShellRoute` で各スタックの状態を保持） |
| バックエンド・認証 | [supabase_flutter](https://pub.dev/packages/supabase_flutter)（PKCE）、[jwt_decode](https://pub.dev/packages/jwt_decode) |
| ディープリンク（メール認証コールバック） | [app_links](https://pub.dev/packages/app_links) |
| 状態管理 | [flutter_riverpod](https://pub.dev/packages/flutter_riverpod) / [hooks_riverpod](https://pub.dev/packages/hooks_riverpod)、[flutter_hooks](https://pub.dev/packages/flutter_hooks) |
| 環境変数 | [flutter_dotenv](https://pub.dev/packages/flutter_dotenv) |
| ロケール | `flutter_localizations`（`supportedLocales`: 日本語） |
| 画像 | [image_picker](https://pub.dev/packages/image_picker)、[flutter_image_compress](https://pub.dev/packages/flutter_image_compress) ほか |

Dart SDK: `^3.9.2`（`pubspec.yaml` 参照）。Flutter はこの SDK に対応した安定版を用意してください。

## セットアップ

1. リポジトリルートに `.env` を作成します。雛形は `env.example` なので、コピーして値を埋めてください。

   - `SUPABASE_URL`
   - `SUPABASE_ANON_KEY`

   値は Supabase ダッシュボードの Project Settings → API から取得します。

2. `.env` は `pubspec.yaml` の `assets` に含めてビルドに同梱します。**リポジトリにコミットしない**でください（ルートの `.gitignore` で `.env` を除外済み）。

3. **Supabase 側の設定（アプリが動くための前提）**

   - **Authentication → Providers → Anonymous sign-ins** を有効にする（起動時に匿名セッションを確保するため）。
   - **Authentication → URL Configuration → Redirect URLs** に、メール内リンクの戻り先を登録する。
     - モバイル（本リポジトリの iOS/Android 設定と一致）: `io.supabase.recolle://login-callback`（末尾スラッシュなし。定数は `lib/core/constants/auth_redirect.dart` の `kSupabaseAppEmailRedirect`）。
     - Web で動かす場合は、そのオリジン（例: `http://localhost:xxxx`）も Redirect URLs に含める（アプリは `Uri.base.origin` をメール用 `redirectTo` に使います）。

4. 依存関係の取得と実行:

   ```bash
   flutter pub get
   flutter run
   ```

   品質確認の例:

   ```bash
   flutter analyze
   flutter test
   ```

## アプリの動き（概要）

- **セッション**: 起動時にセッションが無ければ匿名サインインを試みます（Supabase で匿名ログインが有効なことが前提）。
- **ルーティング**: セッションが無い間は `/account` など再接続しやすい導線を優先します。旧パスの `/login` は **`/account` へリダイレクト**されます。
- **メール認証・リカバリ**: `app_links` でカスタムスキーム `io.supabase.recolle://login-callback` を受け取り、セッション確立後にアカウントタブや `/reset-password` へ遷移します。
- **タブ UI**: 下部ナビで **ホーム（`/`）** と **アカウント（`/account`）** の 2 タブ。認証状態は Supabase の `onAuthStateChange`（ほか再認証・パスワードリカバリ用のフラグ）を GoRouter の `refreshListenable` に渡し、セッション変化でルートを再評価します。

## プロジェクト構成（`lib/`）

- `core/` … ルーター、テーマ、定数、エラーメッセージなど共通基盤
- `features/records/` … レコード一覧・作成・詳細、モデル、プロバイダ
- `features/account/` … 認証サービス、プロバイダ、アカウント UI
- `components/` … ナビ付きスキャフォールド、チケット風カードなど

## Supabase Edge Functions（任意）

バックエンドを自プロジェクトにデプロイする場合、`supabase/functions/` に Resend 経由の認証メール送信（`resend-auth`）やアカウント削除用（`delete-account`）などの関数があります。必要なシークレット（例: `SUPABASE_SERVICE_ROLE_KEY`、`RESEND_API_KEY`）は各関数のソース内の `Deno.env.get(...)` を参照してください。

## Supabase 無停止（GitHub Actions）

無料プランは約 7 日間の非アクティブでプロジェクトが一時停止します。`.github/workflows/supabase-keep-alive.yml` が 3 日ごとに Supabase API へ ping し、停止を防ぎます。

GitHub リポジトリの **Settings → Secrets and variables → Actions** に、`.env` と同じ値で次を登録してください。

| Secret 名 | 値 |
|-----------|-----|
| `SUPABASE_URL` | Supabase プロジェクト URL |
| `SUPABASE_ANON_KEY` | Supabase anon（公開）キー |

登録後、**Actions** タブから `Supabase Keep Alive` を手動実行して動作確認できます。

## 参考リンク

- [Flutter ドキュメント](https://docs.flutter.dev/)
