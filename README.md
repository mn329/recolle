# recolle

ライブ・映画・本などの体験を記録する Flutter アプリです。チケット画像・セットリスト・MC メモ・感想などをまとめて残せるデータモデルを中心に、Supabase 認証と連携した構成になっています。アプリ表示名（`MaterialApp` の `title`）は **recolle** です。

## 技術スタック

| 領域               | 利用パッケージ                                                                                                                                                                              |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| ルーティング       | [go_router](https://pub.dev/packages/go_router)（タブは `StatefulShellRoute` で各スタックの状態を保持）                                                                                     |
| バックエンド・認証 | [supabase_flutter](https://pub.dev/packages/supabase_flutter)、[sign_in_with_apple](https://pub.dev/packages/sign_in_with_apple)、[google_sign_in](https://pub.dev/packages/google_sign_in) |
| 状態管理           | [flutter_riverpod](https://pub.dev/packages/flutter_riverpod) / [hooks_riverpod](https://pub.dev/packages/hooks_riverpod)、[flutter_hooks](https://pub.dev/packages/flutter_hooks)          |
| 環境変数           | [flutter_dotenv](https://pub.dev/packages/flutter_dotenv)                                                                                                                                   |
| ロケール           | `flutter_localizations`（`supportedLocales`: 日本語）                                                                                                                                       |
| 画像               | [image_picker](https://pub.dev/packages/image_picker)、[flutter_image_compress](https://pub.dev/packages/flutter_image_compress) ほか                                                       |

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

`.env` の Google のクライアント ID が空のあいだは、アプリに「Google で続ける」を出しません（押しても設定エラーになるだけのため）。

## アプリの動き（概要）

- **セッション**: 起動時にセッションが無ければ匿名サインインを試みます（Supabase で匿名ログインが有効なことが前提）。電波が悪くても起動が止まらないよう、8 秒で打ち切ります。
- **通信が不安定なとき**: 記録の一覧は端末にも保存し（`core/data/json_list_file_cache.dart`）、オフラインや読み込みの失敗時も最後に取れた一覧を出したままにします。読み込みに失敗したときは上部のお知らせから再読み込みできます。Edge Function の呼び出しはタイムアウトを付け、失敗は分かるメッセージに変えて伝えます（`core/network/edge_function.dart`）。
- **アカウント**: 匿名ユーザーが Apple / Google で続けると同じユーザーに連携され、記録はそのまま引き継がれます。そのアカウントが既に別ユーザーに連携済みなら、確認のうえそちらへ切り替えます。
- **ルーティング**: セッションが無い間は `/account` へ誘導します。旧パスの `/login`・`/forgot-password`・`/reset-password` も `/account` へリダイレクトされます。
- **iOS ライクな UI**: `ThemeData.platform` を iOS に固定し、全画面でスワイプで戻る・バウンススクロールを有効にしています。タブバーは画面下に浮かぶリキッドグラス（[liquid_glass_renderer](https://pub.dev/packages/liquid_glass_renderer)、`components/liquid_glass_tab_bar.dart`。本物の屈折表現は iOS 26 以降かつシェーダー対応環境のみ。それより前の iOS では従来風のすりガラス、「コントラストを上げる」が ON なら不透明なバー、「視差効果を減らす」が ON なら伸び縮みのアニメーションを止める）、各タブはラージタイトル（`LargeTitleScrollView`）、確認は `CupertinoAlertDialog` / アクションシート（`core/widgets/confirm_dialog.dart`）、通知はスナックバーではなく上部のトースト（`AppToast`）です。共通部品は `core/widgets/ios_widgets.dart` にまとめています。記録の作成・編集は iOS のカード型シート（`showCupertinoSheet`）で開き、入力途中のデータを守るためスワイプでは閉じません。
- **ライト / ダーク**: 端末の外観設定（`ThemeMode.system`）に合わせて自動で切り替わります。アクセントはシャンパンゴールドです。色は `core/theme/app_colors.dart` の `AppPalette`（`ThemeExtension`）にライト・ダークの 2 セットで定義し、ウィジェットからは `context.colors.accent` のように参照します。色を直接書かず、足りない色はパレットに追加してください。
- **タブ UI**: 下部ナビで **ホーム（`/`）**・**振り返り（`/insights`）**・**お気に入り（`/favorites`）**・**アカウント（`/account`）** の 4 タブ。router はトップレベル変数なので、ブランチを増減したらホットリロードではなくアプリを再起動してください。認証状態は Supabase の `onAuthStateChange` と再認証中フラグを GoRouter の `refreshListenable` に渡し、セッション変化でルートを再評価します。

- **お気に入りアーティスト**: `favorite_artists` テーブルに保存。記録の `artist_or_author` とは名前で照合します（大文字小文字・スペース・「A × B」などのコラボ表記を吸収、`core/utils/artist_name_match.dart`）。追加シートで候補を選ぶとアーティスト詳細を開くだけで、登録は詳細の ☆ で行います（見たいだけのアーティストが登録されないように）。ライブを記録すると、そのアーティスト（対バン・フェスはお目当ての 1 組）を自動でお気に入りに追加します。編集では新しく加わったアーティストだけを追加し、自分で外したお気に入りは戻しません（`features/favorites/auto_favorite.dart`）。
- **曲・アーティスト情報**: [iTunes Search API](https://performance-partners.apple.com/search-api)（キー不要）でアーティスト名・曲名の補完とアートワークを取得。レート制限（約 20 回/分）があるため入力はデバウンスし、結果はメモリにキャッシュします。
- **アーティスト画像**: iTunes にはアーティスト画像がないため、[Deezer API](https://developers.deezer.com/api)（キー不要）の画像を優先し、見つからなければ iTunes の代表アルバムのジャケットで代用します。以前ジャケットで保存したお気に入りは、起動時に順次アーティスト画像へ置き換えます。
- **アーティスト / 曲詳細**: iTunes の人気曲・収録情報と、Apple Music・Spotify・YouTube Music へのリンク。Apple Music は iTunes が返す正規 URL、Spotify / YouTube Music は無料の検索 API がないため検索結果ページを開きます（アプリがあればアプリで開く）。
- **メールから入力**: 作成画面の「メールから入力」に e+・ローチケ・チケットぴあなどの購入／当選メール本文を貼ると、公演名・出演者・公演日・取得元を入力欄に入れます（`features/records/ticket_mail_parser.dart`）。各社とも公開 API がなく、サイトの自動取得は利用規約に抵触しうるため、本文を端末内で読み取る方式にしています。
- **setlist.fm 連携**: [setlist.fm API](https://api.setlist.fm/docs/1.0/index.html) を Edge Function `setlistfm-search` 経由で検索し、下の「公演名の候補」に使います（下記の設定が必要）。画面の説明文やエラーには外部サービス名を出さず、出典は TMDB・楽天ブックスと合わせてアカウント画面の下部に表示します。
- **これからの公演（AI 検索）**: アーティスト詳細の「公演を探す」で、Gemini が Web（Google 検索、または無料枠では公式サイト）から今後のライブ・フェス出演を集めます（Edge Function `concert-discovery`、`features/music/widgets/upcoming_concerts_section.dart`）。＋を押すと公演名・日付・会場・開場／開演を入れた作成画面が開きます。誤りがありうるので出典リンクを添え、Gemini の規約どおり Google 検索の候補（`google_search_suggestions.dart`）も表示します。無料枠を節約するため、開いただけでは検索せず、結果はアーティストごとに 24 時間キャッシュ（`concert_discovery_cache`）し、キャッシュ外の検索は 1 人 1 日 20 回（匿名のままなら 5 回）まで（`concert_discovery_usage`）、全ユーザー合計で 1 日 300 回まで（`concert_discovery_daily_total`）です。匿名アカウントは作り直せるため、合計の上限で Gemini の無料枠（プロジェクト全体で 1 日 500 回）を 1 人で使い切られないようにしています。
- **公演名の候補**: ライブの作成画面でアーティストを入れてから公演名欄に触れると、今後の公演（上の AI 検索。検索済みなら自動、未検索なら「これからの公演を探す」から）・setlist.fm の直近 100 公演（曲が未登録の公演も含む。ツアー名の途中までの入力でも見つかるよう多めに取る）・自分の過去の記録を候補に出し、入力した文字で絞り込みます。手元の候補に一致するものがなく 3 文字以上入力したときだけ、setlist.fm をツアー名でも検索し、直近にない公演も出します（setlist.fm の一致は単語単位で、単語の途中までの入力では見つかりません）。setlist.fm の上限（1 日 1,440 回）は API キー単位で全ユーザー共有のため、Edge Function は同じ検索の結果を 24 時間キャッシュ（`setlistfm_cache`）します。候補の一覧は高さを抑えてスクロールできます（`features/records/concert_candidates.dart`、`ConcertSuggestions`）。選ぶと公演名に加えて日付・会場・開場／開演、セトリが空なら setlist.fm のセトリも入ります（setlist.fm はローマ字で登録されがちな曲名を、iTunes で日本語の曲名に直します）。セトリを setlist.fm から入れる方法はこの候補に一本化しています。過去の記録はツアーの別日向けなので公演名だけを入れます。
- **映画・本の題名候補**: 映画・本の作成画面で題名を入力すると候補を出し、選ぶと題名と監督／著者を入れます（`features/records/data/work_search_client.dart`、`WorkSuggestions`）。Edge Function `work-search` 経由で、映画は [TMDB](https://developer.themoviedb.org/docs)（邦題・ポスター・公開年、監督は日本語表記があればそれを使う）、本は [楽天ブックス書籍検索 API](https://webservice.rakuten.co.jp/documentation/books-book-search)（紙の本も対象、書影付き。単行本・文庫など同じ題名・著者の本は 1 件にまとめる）を検索します（下記の設定が必要）。入力はデバウンスし、結果はアプリと Edge Function の両方でメモリにキャッシュします。両サービスの規約に従い、アカウント画面の下部に出典を表示しています。
- **ホームの絞り込み**: お気に入りアーティストのチップはライブのときだけ出し、映画・本などに切り替えると絞り込みも外します。
- **対バン・フェス**: ライブは「ワンマン／対バン／フェス」を選べます（`records.event_format`）。対バン・フェスでは出演者ごとにセトリを入れ、★ でお目当てに印を付けます（`records.acts`、`[{artist, songs, is_main, day}]`、`widgets/record_form/acts_editor.dart`）。対バンは最初から 2 組分の欄を出し、セトリは出演者のカードの中で開閉します。`artist_or_author` にはお目当て（いなければ全員）を「／」でつないだ見出しを入れ、一覧やチケットに出します。フェスは最終日（`records.end_date`）を入れると複数日を 1 件にまとめ、開催日から最終日までの日数分「DAY 1・DAY 2…」に分けて出演者を入力でき（`day`）、カレンダーでは期間中の毎日に出し、最終日が終わるまで「これから」に残ります。統計・検索・アーティスト／曲の画面・お気に入りの絞り込みは出演者全員を対象にします（`Record.performances` / `features` / `songsBy`）。ワンマンと従来の記録は `artist_or_author` と `setlist` だけを使います。
- **公演・チケット情報**: ライブの記録には開場・開演・終演の時刻、会場・座席・チケット代を残せます（`records` の `open_time` / `start_time` / `end_time` / `venue` / `seat` / `ticket_price`）。終演が開演より前の時刻なら翌日（オールナイトなど）とみなします。
- **これから / これまで**: ホームは「これから」と「これまで」に分けます（終演時刻があれば終演した時点で、なければ日付が変わった時点で「これまで」へ）。直近の公演は、開場まで → 開演まで → 公演中・終演までと段階的に秒単位でカウントダウンし（開始時刻が未入力の予定は、当日になると「0日」と表示）、これからの記録の詳細画面にも同じカウントダウンを出します（`features/records/record_timeline.dart`、`widgets/event_countdown.dart`）。「これから」「これまで」はそれぞれ見出し右のボタンで並び順を変えられ（日付の近い順／遠い順、古い順／新しい順、ライブならライブ形態ごと。`TimelineSort`）、直近の公演のカードは並び順にかかわらず一番近い予定を出します。
- **振り返り**: 記録のカレンダーと、年別の件数・よく行ったアーティスト／会場・チケット代合計などの集計（`record_calendar.dart` / `record_stats.dart`）。対バン・フェスは出演者全員を「観た」として数え、ライブ数にワンマン・対バン・フェスの内訳と観たアーティスト数を添えます。よく聴いた曲はアーティストと曲名の組で数え、行から曲の詳細へ移れます。ホームと同じお気に入りアーティストのチップ（`favorite_artist_chips.dart`）か、ランキングの行でアーティストを選ぶと、カレンダーも集計もそのアーティストだけになり、初めて・最後に行った日、次の公演、よく聴いた曲、行ったライブの一覧を出します（よく聴いた曲は、対バン・フェスでもそのアーティストの曲だけ）。カレンダーは月の記録を下に一覧し、日を押すとその日に絞ります。集計のライブ数や月別グラフの棒を押すと、その期間に行ったライブの一覧（`live_list_screen.dart`）を開きます。よく行った会場の行を押すと、その会場に行った回数・その会場で聴いた曲のランキング・行ったライブの一覧を出します（`venue_detail_screen.dart`、会場名は表記ゆれを吸収して照合）。
- **チケットの見た目**: ホームのチケット（`TicketFace`）は、右の半券に表紙の写真を券の形で切り抜いて敷き、2 枚以上なら枚数ぶんの点を添えます。写真がなければ半券に「ADMIT ONE」と入れます。
- **記録の詳細**: チケット画像は切り抜かずに全体を見せ、複数枚なら横スワイプで切り替えます（`widgets/ticket_image_carousel.dart`）。高さは写真の縦横比に合わせ、縦画面で撮った写真などは画面の 6 割までに抑えて左右をぼかした同じ写真で埋めます。日付・開場／開演／終演を上に、会場・座席・料金・取得元を切り取り線の下に並べた券面（`widgets/ticket_stub_card.dart`）。セトリ・MCメモ・感想は入力があるものだけ出し、未入力のものは「編集」から追加できる旨をまとめて案内します。
- **Apple Music のプレイリスト**: iOS では、セトリのあるライブの詳細画面から、セトリの曲で Apple Music のプレイリスト（名前は「公演名 日付」）を作れます。曲名から iTunes の `trackId`（= Apple Music の曲 ID）を探し（アーティストの曲一覧 1 回＋見つからない曲だけ 1 曲ずつ最大 10 回、曲名が一致したものだけ使う）、見つからない曲があれば確認してから、iOS の MusicKit でライブラリに作ります（`features/records/record_playlist.dart`、`features/music/data/apple_music_playlist.dart`、`ios/Runner/AppDelegate.swift`）。対バン・フェスは出演者の順に全員の曲を入れます。使う人の Apple Music 加入と iOS 16 以降が必要です（アプリは iOS 14 から動くよう MusicKit を弱リンク）。MusicKit の開発者トークンは OS が自動で発行するのでキーは不要ですが、[Apple Developer の Identifiers](https://developer.apple.com/account/resources/identifiers/list) で App ID `com.ishidaminato.recolle` の **App Services → MusicKit** を有効にしておく必要があります。
- **シェア画像**: 詳細画面の共有ボタンから、チケット風・レシート風の画像（幅 1080px の PNG）を iOS の共有シートへ渡します。差し色は 7 色から選べます。曲は 1 つの一覧につき 40 曲まで載せ、12 曲を超えるとチケットは 2 段組み、レシートは小さい字で詰めます。対バン・フェスは出演者に続けてお目当てのセトリも載せます。
- **ホーム画面ウィジェット（iOS 17 以降）**: 「次の予定」（すべての予定で一番近いもの）・「次のライブ」・「次の映画」・「次のその他の予定」の 4 種類があります。開始時刻がある予定は「12日 5時間」（1 時間ごとに更新）、24 時間を切ると「11時間32分」、当日は開場・開演・終演までの秒単位のカウントダウンです。開始時刻が未入力の予定（時間を決めていないその他の予定など）は日数のみで、当日は「今日」、終了時刻だけあれば「終了まで」を数えます。タイムラインは 3 日分ずつ作り、その末尾で作り直します（作り直しの回数には iOS の上限があるため）。アプリは記録が変わるたびに種類ごとに近い順 5 件を App Group `group.com.ishidaminato.recolle` へ書き込み（[home_widget](https://pub.dev/packages/home_widget)、`features/records/home_widget_sync.dart`）、`ios/RecolleWidget/`（WidgetKit 拡張）が読み取ります。実機で動かすには Apple Developer で App Group を作成し、アプリとウィジェット（`com.ishidaminato.recolle.RecolleWidget`）の両方の App ID に割り当ててください。
- **記録の作成・編集**: 入力内容をホームと同じチケット（`TicketFace`）でプレビューし、その下でチケット画像を 5 枚まで選べます（1 枚目が表紙。サムネイルをタップするとその画像が表紙になり、右上の × で外す）。会場・チケット取得元の欄に触れると、自分の過去の入力（多い順）と定番の候補（主な会場、チケットサイト・ファンクラブなど。種別ごとに変える）をチップで出します（`features/records/field_suggestions.dart`）。公演ページやチケットのページのリンク（`records.link_url`、http(s) のみ・2,000 文字まで）も残せ、詳細画面から開けます。スキームを省いた URL は `https://` を補い、メールから入力ではチケットサイトのリンクを、これからの公演からの作成では出典のページを入れます。画像は `records.ticket_image_urls` に並び順どおり保存し、旧版アプリ向けに先頭を `ticket_image_url` にも入れます。外した画像・消した記録の画像はストレージ（`ticket-images`）からも消します。`ticket-images` は本人しか取得できない非公開のバケットで、保存している URL は場所を表す識別子として使い、表示は認証つきの窓口から本人のトークンで取得します（`RecordsRepository.ticketImageRequest`）。保存は 20 秒（画像のアップロードは 60 秒）で打ち切ります。応答がないまま打ち切ったときは、サーバーに反映された可能性があるので入力と上げた画像を残し、新しい記録の ID はアプリで決めて upsert するので、保存し直しても二重になりません。種別ごとに入力欄の呼び方が変わり、セットリスト・MC メモはライブのときだけ入力・保存します。セトリの曲名欄に触れると、入力前はアーティストの人気曲、入力中は曲名の候補を出します。複数行のセトリを貼り付けると 1 行ずつ追加し、全曲に付いた「1.」「M1」などの番号を取り、「【アンコール】」「EN1」などはアンコールの区切りにします。ボタンで MC・アンコール・リハ／本番の行を入れられます。区切りと MC は `setlist`（`acts.songs`）に `--- アンコール ---` や `MC` の行として保存し（DB の形は変えない）、番号・曲数・統計・検索・シェア画像では曲として数えません（`models/setlist_entry.dart`）。部品は `features/records/widgets/record_form/`。

## プロジェクト構成（`lib/`）

- `core/` … ルーター、テーマ、定数、エラーメッセージなど共通基盤
- `features/records/` … レコード一覧・作成・詳細、モデル、プロバイダ
- `features/favorites/` … お気に入りアーティスト（タブ・追加シート・アーティスト別一覧）
- `features/music/` … iTunes Search API / Deezer API / setlist.fm のクライアント
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

`supabase/functions/place-search` は Google Places API (New) のテキスト検索のプロキシです（会場・映画館の候補用。API キーをアプリに埋め込まないため）。関数内でセッションのユーザーを検証します。

1. Google Cloud で Places API (New) を有効にして API キーを発行（請求先アカウントが必要）。
2. シークレットを登録してデプロイ:

```bash
supabase secrets set GOOGLE_PLACES_API_KEY=<発行したキー> --project-ref <project-ref>
supabase functions deploy place-search --project-ref <project-ref>
```

キー未登録の間、会場欄の候補には「場所の検索が未設定です」と表示します。

`supabase/functions/concert-discovery` は Gemini API のプロキシです。既定のモデルは `gemini-3.5-flash-lite` です（`GEMINI_MODEL` で変更可）。Gemini 3.x の無料枠では Google 検索グラウンディングの上限が 0 で必ず 429 になるため、既定では試さずに [MusicBrainz](https://musicbrainz.org/doc/MusicBrainz_API) に登録された公式サイト（official homepage）とサイト内のライブ・ツアー告知らしいページを、無料枠で使える URL context で読み取って公演を集めます。このときの出典は公式サイトで、公演の告知 URL は実際に読んだページのものだけを載せます。MusicBrainz に公式サイトが登録されていないアーティストは探せません（`discovery_no_official_site`）。課金を有効にしたうえでシークレット `GEMINI_SEARCH_GROUNDING=true` を設定すると、先に検索グラウンディング（月 5,000 回まで無料）を使うようになり、公式サイト以外の告知も拾えます（`supabase secrets set GEMINI_SEARCH_GROUNDING=true`）。無料枠では入力内容（アーティスト名）が Google のサービス改善に使われることがあります。

1. [Google AI Studio](https://aistudio.google.com/apikey) で API キーを発行（無料、請求先の登録は不要）。
2. シークレットを登録してデプロイ:

```bash
supabase secrets set GEMINI_API_KEY=<発行したキー> --project-ref <project-ref>
supabase functions deploy concert-discovery --project-ref <project-ref>
```

キー未登録の間、「公演を探す」は「公演検索が未設定です」と表示します。

`supabase/functions/work-search` は映画（TMDB）・本（楽天ブックス）の題名検索のプロキシです（API キーをアプリに埋め込まないため）。どちらも無料で、1 回の検索で TMDB は最大 11 回（検索 1 回＋作品ごとのクレジット＋監督の日本語名。監督名は関数内でキャッシュ）、楽天は 1 回呼びます。楽天の上限は 1 秒 1 回程度で全ユーザー共有のため、超えると「混み合っています」と表示します。

1. [TMDB の API 設定](https://www.themoviedb.org/settings/api)で API を申請し、「API 読み込みアクセストークン」（`eyJ...` で始まる長い文字列）を控える（無料・非商用）。
2. [楽天ウェブサービス](https://webservice.rakuten.co.jp/app/list)でアプリを登録する。アプリケーションタイプは **Web アプリケーション** を選び、許可する Web サイトに `<project-ref>.supabase.co` を入れる。発行されたアプリケーション ID（UUID 形式）とアクセスキー（`pk_...`）を控える。Edge Functions は接続元 IP が固定でないため、バックエンドサービス型は使えません（関数は Referer / Origin に `SUPABASE_URL` を付けて呼びます）。
3. シークレットを登録してデプロイ:

```bash
supabase secrets set TMDB_API_TOKEN=<読み込みアクセストークン> RAKUTEN_APPLICATION_ID=<アプリ ID> RAKUTEN_ACCESS_KEY=<pk_...> --project-ref <project-ref>
supabase functions deploy work-search --project-ref <project-ref>
```

キー未登録の間、題名の候補欄には「映画の検索が未設定です」「本の検索が未設定です」と表示します。

## DB マイグレーション

`supabase/migrations/` にスキーマ変更を置いています（`favorite_artists` の作成、`records` の RLS 最適化など）。

次のマイグレーションは、アプリや Edge Function との順番を守って適用してください。

- `20260929080000_add_record_link_url.sql`：リンクを保存する版のアプリを配布する前に適用する（新しい版は保存時に `link_url` を送るため、列がないと保存に失敗する）。

- `20260929055000_drop_old_concert_discovery_quota.sql`：`20260929050000_concert_discovery_global_quota.sql` を適用し、`concert-discovery` をデプロイしてから適用する（旧版の関数が古い回数制限を呼ぶため）。
- `20260929070000_make_ticket_images_private.sql`：認証つきで画像を取得する版のアプリが行き渡ってから適用する（公開 URL で表示している旧版アプリでは画像が出なくなるため）。

## Supabase 無停止（GitHub Actions）

無料プランは約 7 日間「DB へのユーザークエリ」が少ないと一時停止します。`.github/workflows/supabase-keep-alive.yml` が毎日 2 回（日本時間 12:00 / 24:00）`records` へ軽量な SELECT を送り、停止を防ぎます（Auth health だけでは足りないことがあります）。すでに一時停止したプロジェクトはダッシュボードで Resume が必要です。

GitHub リポジトリの **Settings → Secrets and variables → Actions** に、`.env` と同じ値で次を登録してください（`gh secret set <名前>` でも可）。

| Secret 名                  | 値                                                                     |
| -------------------------- | ---------------------------------------------------------------------- |
| `SUPABASE_URL`             | Supabase プロジェクト URL（例: `https://abcdefghijklmno.supabase.co`） |
| `SUPABASE_PUBLISHABLE_KEY` | Supabase publishable（公開）キー（`sb_publishable_...`）               |

**よくある設定ミス**

- `<project-ref>` のようなプレースホルダーをそのまま入れている
- `https://` を付けずに `abcdefghijklmno.supabase.co` だけ入れている（`https://` 必須）
- 引用符で囲んでいる（`"https://..."` は不要）

登録後、**Actions** タブから `Supabase Keep Alive` を手動実行して動作確認できます。

## 参考リンク

- [Flutter ドキュメント](https://docs.flutter.dev/)
