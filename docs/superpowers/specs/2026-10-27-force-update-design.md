# 強制アップデート 設計

## 目的

重大な不具合や脆弱性が見つかったとき、修正前のアプリを使い続けているユーザーに、App Store からのアップデートを必須にできるようにする。

- 配信先は App Store のみ（iOS）。App Store ID: `6762868760`
- 最低バージョンはアプリを出し直さずにサーバー側で変えられること
- この仕組みが入ったビルドより前に配布済みの版は対象にできない（効くのは次のアップデートから）

## 方針

Supabase に最低バージョンを 1 行だけ置き、アプリは起動時と前面に戻ったときに自分のバージョンと比べる。下回っていれば全画面でブロックし、App Store へ誘導する。

検討して採らなかった案:

- App Store の最新版と比べる（iTunes Lookup API）: 新しい版を出すたびに全員が対象になり、制御できない
- Edge Function で返す: テーブルを読むのと同じことに、デプロイ対象が 1 つ増えるだけ

## サーバー（Supabase）

マイグレーション `supabase/migrations/<timestamp>_app_config.sql`:

```sql
create table public.app_config (
  id boolean primary key default true check (id),  -- 1 行だけにする
  min_ios_version text not null check (min_ios_version ~ '^\d+(\.\d+){0,2}$')
);
alter table public.app_config enable row level security;
create policy "誰でも読める" on public.app_config for select to anon, authenticated using (true);
insert into public.app_config (min_ios_version) values ('1.0.0');
```

- 書き込みのポリシーは作らない（ダッシュボードの SQL エディタやテーブル編集から service role で変える）
- 初期値は `1.0.0`（今の利用者は誰もブロックされない）。必要になったら値を上げる

## アプリ

### バージョン比較 `lib/core/app_update/app_version.dart`

- `"1.2.3"` を `[1, 2, 3]` にして桁ごとに比べる。足りない桁は 0（`"1.2"` は `1.2.0`）
- 形式が不正な値は「ブロックしない」側に倒す

### 取得 `lib/core/app_update/force_update_provider.dart`

- `package_info_plus` で自分のバージョン（`1.1.4` など。ビルド番号は使わない）を取る
- `app_config` の `min_ios_version` を読む（タイムアウト 5 秒）
- 結果: `required`（ブロック）か `ok`。**読めなかったとき（オフライン・エラー・タイムアウト・行がない）は `ok`**。オフラインでも記録を見られる今の体験を壊さないため
- iOS 以外（テスト・将来の Android）では確認しない
- デモモード（`DEMO_MODE`）では確認しない

### ブロック画面 `lib/core/app_update/force_update_gate.dart`

- `buildAppRoot` で全画面の一番外側に重ねる。`required` のときだけ、下の画面への操作を受け付けない全画面を出す
- 中身: 見出し「アップデートが必要です」、説明文、ボタン「App Store を開く」（`https://apps.apple.com/app/id6762868760` を `url_launcher` の外部アプリで開く）
- 閉じる手段はない
- アプリが前面に戻ったとき（`AppLifecycleState.resumed`）に確認し直す。ストアから戻ってきても古いままなら出し続ける

## テスト

- `app_version` の比較: 同じ・小さい・大きい・桁数が違う・不正な値
- provider: 最低バージョンより古い → `required` / 同じ・新しい → `ok` / 取得エラー・タイムアウト・行なし → `ok`
- ブロック画面: `required` で表示されボタンがあること、`ok` で何も出ないこと

## やらないこと

- 任意アップデートのお知らせ（閉じられるもの）
- Android の最低バージョン（配信していない）
- 文言をサーバーから変える仕組み

## リリース

1. PR #15 → #16 → この機能の PR の順に `main` へマージ
2. Supabase にマイグレーションを適用（本番）
3. `pubspec.yaml` を `1.1.4+29` にする
4. `flutter build ipa` → App Store Connect にアップロード → TestFlight で配信
5. 審査への提出は TestFlight で確認したあとに手動で行う
