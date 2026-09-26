# recolle

ライブ・映画・本などの体験を記録する Flutter アプリです。チケット画像・セットリスト・MC メモ・感想などをまとめて残せるデータモデルを中心に、Supabase 認証と連携した構成になっています。アプリ表示名（`MaterialApp` の `title`）は **recolle** です。

## 技術スタック

| 領域 | 利用パッケージ |
|------|----------------|
| ルーティング | [go_router](https://pub.dev/packages/go_router)（タブは `StatefulShellRoute` で各スタックの状態を保持） |
| バックエンド・認証 | [supabase_flutter](https://pub.dev/packages/supabase_flutter)、[sign_in_with_apple](https://pub.dev/packages/sign_in_with_apple)、[google_sign_in](https://pub.dev/packages/google_sign_in) |
| 状態管理 | [flutter_riverpod](https://pub.dev/packages/flutter_riverpod) / [hooks_riverpod](https://pub.dev/packages/hooks_riverpod)、[flutter_hooks](https://pub.dev/packages/flutter_hooks) |
| 環境変数 | [flutter_dotenv](https://pub.dev/packages/flutter_dotenv) |
| ロケール | `flutter_localizations`（`supportedLocales`: 日本語） |
| 画像 | [image_picker](https://pub.dev/packages/image_picker)、[flutter_image_compress](https://pub.dev/packages/flutter_image_compress) ほか |

Dart SDK: `^3.9.2`（`pubspec.yaml` 参照）。Flutter はこの SDK に対応した安定版を用意してください。

## セットアップ

1. リポジトリルートに `.env` を作成します。雛形は `env.example` なので、コピーして値を埋めてください。

   - `SUPABASE_URL`
   - `SUPABASE_PUBLISHABLE_KEY`（`sb_publishable_...` 形式の公開キー）
   - `GOOGLE_WEB_CLIENT_ID` / `GOOGLE_IOS_CLIENT_ID`（下記「Apple / Google ログインの設定」参照）

   Supabase の値は Project Settings → API Keys から取得します。`service_role` / `sb_secret_...` などの秘密鍵は **絶対に入れない** でください（`.env` はアプリに同梱されます）。

2. `.env` は `pubspec.yaml` の `assets` に含めてビルドに同梱します。**リポジトリにコミットしない**でください（ルートの `.gitignore` で `.env` を除外済み）。

3. Supabase の **Authentication → Sign In / Providers** で **Anonymous sign-ins** と **Allow manual linking** を有効にします（起動時の匿名セッションと、匿名から Apple / Google への引き継ぎに必要）。

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

## Apple / Google ログインの設定

メールアドレスでの登録・ログインは廃止し、メール送信（SMTP）を使わない構成です。各 SDK で取得した ID トークンを Supabase の `signInWithIdToken` / `linkIdentityWithIdToken` に渡します。

**Sign in with Apple（iOS のみ表示）**

1. Apple Developer の Identifiers で App ID `com.ishidaminato.recolle` の **Sign In with Apple** を有効にする（`ios/Runner/Runner.entitlements` は設定済み）。
2. Supabase の **Authentication → Sign In / Providers → Apple** を有効にし、**Client IDs** に `com.ishidaminato.recolle` を入れる（ネイティブのみならシークレットキーは不要）。

**Google**

1. Google Cloud Console の「API とサービス → 認証情報」で OAuth クライアント ID を作る。
   - **ウェブアプリケーション**: ID を `.env` の `GOOGLE_WEB_CLIENT_ID` に入れる。
   - **iOS**（バンドル ID `com.ishidaminato.recolle`）: ID を `.env` の `GOOGLE_IOS_CLIENT_ID` に入れ、逆順にした値（`com.googleusercontent.apps.xxxx`）を `ios/Flutter/GoogleSignIn.xcconfig` に入れる。
   - **Android**（パッケージ名 `com.ishidaminato.recolle` と署名の SHA-1）: アプリ側の設定は不要。
2. Supabase の **Authentication → Sign In / Providers → Google** を有効にし、**Client IDs** にウェブと iOS の ID をカンマ区切りで入れる。

以前メールアドレスで登録したユーザーは、同じメールアドレスの Google アカウントでログインすると Supabase の自動リンクで既存アカウント（記録）に入れます。

## アプリの動き（概要）

- **セッション**: 起動時にセッションが無ければ匿名サインインを試みます（Supabase で匿名ログインが有効なことが前提）。
- **アカウント**: 匿名ユーザーが Apple / Google で続けると同じユーザーに連携され、記録はそのまま引き継がれます。そのアカウントが既に別ユーザーに連携済みなら、確認のうえそちらへ切り替えます。
- **ルーティング**: セッションが無い間は `/account` へ誘導します。旧パスの `/login`・`/forgot-password`・`/reset-password` も `/account` へリダイレクトされます。
- **iOS ライクな UI**: `ThemeData.platform` を iOS に固定し、全画面でスワイプで戻る・バウンススクロールを有効にしています。タブバーは画面下に浮かぶリキッドグラス（[liquid_glass_renderer](https://pub.dev/packages/liquid_glass_renderer)、`components/liquid_glass_tab_bar.dart`。シェーダーは Impeller 専用のため、それ以外の環境では軽量なすりガラスで代用）、各タブはラージタイトル（`LargeTitleScrollView`）、確認は `CupertinoAlertDialog` / アクションシート（`core/widgets/confirm_dialog.dart`）、通知はスナックバーではなく上部のトースト（`AppToast`）です。共通部品は `core/widgets/ios_widgets.dart` にまとめています。記録の作成・編集は iOS のカード型シート（`showCupertinoSheet`）で開き、入力途中のデータを守るためスワイプでは閉じません。
- **タブ UI**: 下部ナビで **ホーム（`/`）**・**お気に入り（`/favorites`）**・**アカウント（`/account`）** の 3 タブ。認証状態は Supabase の `onAuthStateChange` と再認証中フラグを GoRouter の `refreshListenable` に渡し、セッション変化でルートを再評価します。

- **お気に入りアーティスト**: `favorite_artists` テーブルに保存。記録の `artist_or_author` とは名前で照合します（大文字小文字・スペース・「A × B」などのコラボ表記を吸収、`core/utils/artist_name_match.dart`）。
- **曲・アーティスト情報**: [iTunes Search API](https://performance-partners.apple.com/search-api)（キー不要）でアーティスト名・曲名の補完とアートワークを取得。レート制限（約 20 回/分）があるため入力はデバウンスし、結果はメモリにキャッシュします。
- **アーティスト / 曲詳細**: iTunes の人気曲・収録情報と、Apple Music・Spotify・YouTube Music へのリンク。Apple Music は iTunes が返す正規 URL、Spotify / YouTube Music は無料の検索 API がないため検索結果ページを開きます（アプリがあればアプリで開く）。
- **セットリスト取り込み**: [setlist.fm API](https://api.setlist.fm/docs/1.0/index.html) を Edge Function `setlistfm-search` 経由で検索します（下記の設定が必要）。
- **記録の作成・編集**: 入力内容をホームと同じチケット（`TicketFace`）でプレビューし、タップで券面画像を選びます。種別ごとに入力欄の呼び方が変わり、セットリスト・MC メモはライブのときだけ入力・保存します。部品は `features/records/widgets/record_form/`。

## プロジェクト構成（`lib/`）

- `core/` … ルーター、テーマ、定数、エラーメッセージなど共通基盤
- `features/records/` … レコード一覧・作成・詳細、モデル、プロバイダ
- `features/favorites/` … お気に入りアーティスト（タブ・追加シート・アーティスト別一覧）
- `features/music/` … iTunes Search API / setlist.fm のクライアント
- `features/account/` … 認証サービス、プロバイダ、アカウント UI
- `components/` … ナビ付きスキャフォールド、チケット風カードなど

## Supabase Edge Functions（任意）

`supabase/functions/delete-account` はアカウント削除用の関数です。使用する `SUPABASE_URL` / `SUPABASE_ANON_KEY` / `SUPABASE_SERVICE_ROLE_KEY` は Supabase が自動で注入するため、シークレットの手動登録は不要です。

```bash
supabase functions deploy delete-account --project-ref <project-ref>
```

`supabase/functions/setlistfm-search` は setlist.fm のプロキシです（API キーをアプリに埋め込まないため）。関数内でセッションのユーザーを検証するので、ログイン（匿名含む）していない呼び出しは 401 になります。

1. [setlist.fm の API 設定](https://www.setlist.fm/settings/api)で API キーを発行（無料・非商用）。
2. シークレットを登録してデプロイ:

```bash
supabase secrets set SETLISTFM_API_KEY=<発行したキー> --project-ref <project-ref>
supabase functions deploy setlistfm-search --project-ref <project-ref>
```

キー未登録の間、アプリの「setlist.fm」ボタンは「連携が未設定です」と表示します。

## DB マイグレーション

`supabase/migrations/` にスキーマ変更を置いています（`favorite_artists` の作成、`records` の RLS 最適化など）。

## Supabase 無停止（GitHub Actions）

無料プランは約 7 日間「DB へのユーザークエリ」が少ないと一時停止します。`.github/workflows/supabase-keep-alive.yml` が毎日 2 回（日本時間 12:00 / 24:00）`records` へ軽量な SELECT を送り、停止を防ぎます（Auth health だけでは足りないことがあります）。すでに一時停止したプロジェクトはダッシュボードで Resume が必要です。

GitHub リポジトリの **Settings → Secrets and variables → Actions** に、`.env` と同じ値で次を登録してください（`gh secret set <名前>` でも可）。

| Secret 名 | 値 |
|-----------|-----|
| `SUPABASE_URL` | Supabase プロジェクト URL（例: `https://abcdefghijklmno.supabase.co`） |
| `SUPABASE_PUBLISHABLE_KEY` | Supabase publishable（公開）キー（`sb_publishable_...`） |

**よくある設定ミス**

- `<project-ref>` のようなプレースホルダーをそのまま入れている
- `https://` を付けずに `abcdefghijklmno.supabase.co` だけ入れている（`https://` 必須）
- 引用符で囲んでいる（`"https://..."` は不要）

登録後、**Actions** タブから `Supabase Keep Alive` を手動実行して動作確認できます。

## 参考リンク

- [Flutter ドキュメント](https://docs.flutter.dev/)
