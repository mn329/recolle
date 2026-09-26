-- 生成 AI（Gemini + Google 検索）で集めたアーティストの今後の公演。
-- Edge Function `concert-discovery` だけがサービスロールで読み書きする（アプリからは直接触らない）。

-- 同じアーティストの検索結果を全ユーザーで共有し、Gemini の無料枠（1 日 500 回）を節約する。
create table public.concert_discovery_cache (
  artist_key text primary key check (char_length(artist_key) between 1 and 100),
  artist_name text not null,
  events jsonb not null default '[]'::jsonb,
  sources jsonb not null default '[]'::jsonb,
  search_entry_point text,
  fetched_at timestamptz not null default now()
);

comment on table public.concert_discovery_cache is 'アーティストごとの今後の公演の検索結果キャッシュ（Edge Function 専用）';
comment on column public.concert_discovery_cache.artist_key is '表記ゆれをまとめたアーティスト名（小文字・空白除去）';
comment on column public.concert_discovery_cache.search_entry_point is 'Google 検索の候補表示用 HTML（規約上、結果と一緒に表示が必要）';

-- 1 人が無料枠を使い切らないよう、キャッシュに当たらなかった検索の回数を日ごとに数える。
create table public.concert_discovery_usage (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  count integer not null default 0 check (count >= 0),
  primary key (user_id, day)
);

comment on table public.concert_discovery_usage is '今後の公演の検索（キャッシュ外）のユーザー別・日別回数（Edge Function 専用）';

-- ポリシーを作らないので、anon / authenticated からは読み書きできない
alter table public.concert_discovery_cache enable row level security;
alter table public.concert_discovery_usage enable row level security;

-- 上限内なら回数を 1 増やして true を返す。同時に呼ばれても上限を超えないよう 1 文で数える。
create function public.consume_concert_discovery_quota(p_user_id uuid, p_limit integer)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  insert into public.concert_discovery_usage as u (user_id, day, count)
  values (p_user_id, (now() at time zone 'Asia/Tokyo')::date, 1)
  on conflict (user_id, day) do update
    set count = u.count + 1
    where u.count < p_limit
  returning u.count into v_count;
  return v_count is not null;
end;
$$;

revoke all on function public.consume_concert_discovery_quota(uuid, integer) from public, anon, authenticated;
grant execute on function public.consume_concert_discovery_quota(uuid, integer) to service_role;
