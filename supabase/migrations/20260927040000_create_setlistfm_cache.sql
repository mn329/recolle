-- setlist.fm の検索結果。Edge Function `setlistfm-search` だけがサービスロールで読み書きする。

-- setlist.fm の上限（1 日 1,440 回・1 秒 2 回）は API キー単位で全ユーザーが共有するため、
-- 同じ検索は一定時間ここから返し、setlist.fm を呼ばない。
create table public.setlistfm_cache (
  cache_key text primary key check (char_length(cache_key) between 1 and 500),
  setlists jsonb not null default '[]'::jsonb,
  fetched_at timestamptz not null default now()
);

comment on table public.setlistfm_cache is 'setlist.fm の検索結果キャッシュ（Edge Function 専用）';
comment on column public.setlistfm_cache.cache_key is '検索条件（表記ゆれをまとめたアーティスト名・日付・ツアー名など）をつないだもの';

-- 期限切れの行をまとめて消すため
create index setlistfm_cache_fetched_at_idx on public.setlistfm_cache (fetched_at);

-- ポリシーを作らないので、anon / authenticated からは読み書きできない
alter table public.setlistfm_cache enable row level security;
