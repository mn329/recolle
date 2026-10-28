-- 記録一覧はリアルタイム購読（supabase_flutter の stream）で読むが、records が配信対象に入っていなかった。
-- realtime_client 2.9 以降はこのとき購読エラーを画面まで返すので、「最新の記録を読み込めませんでした」が出たり消えたりしていた。
-- 配信にも RLS がかかり、アプリは自分の user_id に絞って購読する。
alter publication supabase_realtime add table public.records;
