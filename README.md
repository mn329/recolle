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
- **iOS ライクな UI**: `ThemeData.platform` を iOS に固定し、全画面でスワイプで戻る・バウンススクロールを有効にしています。タブバーは画面下に浮かぶリキッドグラス（[liquid_glass_renderer](https://pub.dev/packages/liquid_glass_renderer)、`components/liquid_glass_tab_bar.dart`。本物の屈折表現は iOS 26 以降かつシェーダー対応環境のみ。それより前の iOS では従来風のすりガラス、「コントラストを上げる」が ON なら不透明なバー、「視差効果を減らす」が ON なら伸び縮みのアニメーションを止める）、各タブはラージタイトル（`LargeTitleScrollView`）、確認は `CupertinoAlertDialog` / アクションシート（`core/widgets/confirm_dialog.dart`）、通知はスナックバーではなく上部のトースト（`AppToast`）です。共通部品は `core/widgets/ios_widgets.dart` にまとめています。記録の作成・編集は iOS のカード型シート（`showCupertinoSheet`）で開き、入力途中のデータを守るためスワイプでは閉じません。
- **ライト / ダーク**: 端末の外観設定（`ThemeMode.system`）に合わせて自動で切り替わります。アクセントはシャンパンゴールドです。色は `core/theme/app_colors.dart` の `AppPalette`（`ThemeExtension`）にライト・ダークの 2 セットで定義し、ウィジェットからは `context.colors.accent` のように参照します。色を直接書かず、足りない色はパレットに追加してください。
- **タブ UI**: 下部ナビで **ホーム（`/`）**・**振り返り（`/insights`）**・**お気に入り（`/favorites`）**・**アカウント（`/account`）** の 4 タブ。router はトップレベル変数なので、ブランチを増減したらホットリロードではなくアプリを再起動してください。認証状態は Supabase の `onAuthStateChange` と再認証中フラグを GoRouter の `refreshListenable` に渡し、セッション変化でルートを再評価します。

- **お気に入りアーティスト**: `favorite_artists` テーブルに保存。記録の `artist_or_author` とは名前で照合します（大文字小文字・スペース・「A × B」などのコラボ表記を吸収、`core/utils/artist_name_match.dart`）。追加シートで候補を選ぶとアーティスト詳細を開くだけで、登録は詳細の ☆ で行います（見たいだけのアーティストが登録されないように）。
- **曲・アーティスト情報**: [iTunes Search API](https://performance-partners.apple.com/search-api)（キー不要）でアーティスト名・曲名の補完とアートワークを取得。レート制限（約 20 回/分）があるため入力はデバウンスし、結果はメモリにキャッシュします。
- **アーティスト / 曲詳細**: iTunes の人気曲・収録情報と、Apple Music・Spotify・YouTube Music へのリンク。Apple Music は iTunes が返す正規 URL、Spotify / YouTube Music は無料の検索 API がないため検索結果ページを開きます（アプリがあればアプリで開く）。
- **メールから入力**: 作成画面の「メールから入力」に e+・ローチケ・チケットぴあなどの購入／当選メール本文を貼ると、公演名・出演者・公演日・取得元を入力欄に入れます（`features/records/ticket_mail_parser.dart`）。各社とも公開 API がなく、サイトの自動取得は利用規約に抵触しうるため、本文を端末内で読み取る方式にしています。
- **setlist.fm 連携**: [setlist.fm API](https://api.setlist.fm/docs/1.0/index.html) を Edge Function `setlistfm-search` 経由で検索し、下の「公演名の候補」に使います（下記の設定が必要）。
- **これからの公演（AI 検索）**: アーティスト詳細の「公演を探す」で、Gemini が Web（Google 検索、または無料枠では公式サイト）から今後のライブ・フェス出演を集めます（Edge Function `concert-discovery`、`features/music/widgets/upcoming_concerts_section.dart`）。＋を押すと公演名・日付・会場・開場／開演を入れた作成画面が開きます。誤りがありうるので出典リンクを添え、Gemini の規約どおり Google 検索の候補（`google_search_suggestions.dart`）も表示します。無料枠を節約するため、開いただけでは検索せず、結果はアーティストごとに 24 時間キャッシュ（`concert_discovery_cache`）し、キャッシュ外の検索は 1 人 1 日 20 回まで（`concert_discovery_usage`）です。
- **公演名の候補**: ライブの作成画面でアーティストを入れてから公演名欄に触れると、今後の公演（上の AI 検索。検索済みなら自動、未検索なら「これからの公演を探す」から）・setlist.fm の直近 100 公演（曲が未登録の公演も含む。ツアー名の途中までの入力でも見つかるよう多めに取る）・自分の過去の記録を候補に出し、入力した文字で絞り込みます。手元の候補に一致するものがなく 3 文字以上入力したときだけ、setlist.fm をツアー名でも検索し、直近にない公演も出します（setlist.fm の一致は単語単位で、単語の途中までの入力では見つかりません）。setlist.fm の上限（1 日 1,440 回）は API キー単位で全ユーザー共有のため、Edge Function は同じ検索の結果を 24 時間キャッシュ（`setlistfm_cache`）します。候補の一覧は高さを抑えてスクロールできます（`features/records/concert_candidates.dart`、`ConcertSuggestions`）。選ぶと公演名に加えて日付・会場・開場／開演、セトリが空なら setlist.fm のセトリも入ります（setlist.fm はローマ字で登録されがちな曲名を、iTunes で日本語の曲名に直します）。セトリを setlist.fm から入れる方法はこの候補に一本化しています。過去の記録はツアーの別日向けなので公演名だけを入れます。
- **公演・チケット情報**: ライブの記録には開場・開演・終演の時刻、会場・座席・チケット代を残せます（`records` の `open_time` / `start_time` / `end_time` / `venue` / `seat` / `ticket_price`）。終演が開演より前の時刻なら翌日（オールナイトなど）とみなします。
- **対バン・フェス**: ライブは「ワンマン／対バン／フェス」を選べます（`records.event_format`）。対バン・フェスでは出演者ごとにセトリを入れ、★ でお目当てに印を付けます（`records.acts`、`[{artist, songs, is_main}]`、`widgets/record_form/acts_editor.dart`）。`artist_or_author` にはお目当て（いなければ全員）を「／」でつないだ見出しを入れ、一覧やチケットに出します。フェスは最終日（`records.end_date`）を入れると複数日を 1 件にまとめ、カレンダーでは期間中の毎日に出し、最終日が終わるまで「これから」に残ります。統計・検索・アーティスト／曲の画面・お気に入りの絞り込みは出演者全員を対象にします（`Record.performances` / `features` / `songsBy`）。ワンマンと従来の記録は `artist_or_author` と `setlist` だけを使います。
- **これから / これまで**: ホームは「これから」と「これまで」に分けます（終演時刻があれば終演した時点で、なければ日付が変わった時点で「これまで」へ）。直近の公演は、開場まで → 開演まで → 公演中・終演までと段階的に秒単位でカウントダウンし、これからの記録の詳細画面にも同じカウントダウンを出します（`features/records/record_timeline.dart`、`widgets/event_countdown.dart`）。
- **振り返り**: 記録のカレンダーと、年別の件数・よく行ったアーティスト／会場・チケット代合計などの集計（`record_calendar.dart` / `record_stats.dart`）。ホームと同じお気に入りアーティストのチップ（`favorite_artist_chips.dart`）か、ランキングの行でアーティストを選ぶと、カレンダーも集計もそのアーティストだけになり、初めて・最後に行った日、次の公演、よく聴いた曲、行ったライブの一覧を出します。カレンダーは月の記録を下に一覧し、日を押すとその日に絞ります。
- **記録の詳細**: 日付・開場／開演／終演を上に、会場・座席・料金・取得元を切り取り線の下に並べた券面（`widgets/ticket_stub_card.dart`）。セトリ・MCメモ・感想は入力があるものだけ出し、未入力のものは「編集」から追加できる旨をまとめて案内します。
- **シェア画像**: 詳細画面の共有ボタンから、チケット風・レシート風の画像（幅 1080px の PNG）を iOS の共有シートへ渡します。
- **ホーム画面ウィジェット（iOS 17 以降）**: 次の公演までの日数を表示します。アプリは記録が変わるたびに近い順 5 件を App Group `group.com.ishidaminato.recolle` へ書き込み（[home_widget](https://pub.dev/packages/home_widget)、`features/records/home_widget_sync.dart`）、`ios/RecolleWidget/`（WidgetKit 拡張）が読み取ります。実機で動かすには Apple Developer で App Group を作成し、アプリとウィジェット（`com.ishidaminato.recolle.RecolleWidget`）の両方の App ID に割り当ててください。
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

キー未登録の間、公演名の候補には setlist.fm の公演が出ず、「連携が未設定です」と表示します。

`supabase/functions/concert-discovery` は Gemini API のプロキシです。既定のモデルは `gemini-3.5-flash-lite` です（`GEMINI_MODEL` で変更可）。Gemini 3.x の無料枠では Google 検索グラウンディングの上限が 0 で必ず 429 になるため、既定では試さずに [MusicBrainz](https://musicbrainz.org/doc/MusicBrainz_API) に登録された公式サイト（official homepage）とサイト内のライブ・ツアー告知らしいページを、無料枠で使える URL context で読み取って公演を集めます。このときの出典は公式サイトで、公演の告知 URL は実際に読んだページのものだけを載せます。MusicBrainz に公式サイトが登録されていないアーティストは探せません（`discovery_no_official_site`）。課金を有効にしたうえでシークレット `GEMINI_SEARCH_GROUNDING=true` を設定すると、先に検索グラウンディング（月 5,000 回まで無料）を使うようになり、公式サイト以外の告知も拾えます（`supabase secrets set GEMINI_SEARCH_GROUNDING=true`）。無料枠では入力内容（アーティスト名）が Google のサービス改善に使われることがあります。

1. [Google AI Studio](https://aistudio.google.com/apikey) で API キーを発行（無料、請求先の登録は不要）。
2. シークレットを登録してデプロイ:

```bash
supabase secrets set GEMINI_API_KEY=<発行したキー> --project-ref <project-ref>
supabase functions deploy concert-discovery --project-ref <project-ref>
```

キー未登録の間、「公演を探す」は「公演検索が未設定です」と表示します。

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
