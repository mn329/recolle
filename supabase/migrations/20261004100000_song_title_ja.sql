-- ローマ字・英字の曲名の日本語表記を Gemini に聞く（Edge Function `song-title-ja`）。
-- 同じ曲は結果をキャッシュし、Gemini を呼ぶ回数をユーザー別・全体の両方で数えて無料枠を超えないようにする。
-- 上限の作りは venue_search / concert_discovery と同じ。

create table public.song_title_cache (
  artist_key text not null,
  title_key text not null,
  japanese text,
  fetched_at timestamptz not null default now(),
  primary key (artist_key, title_key)
);

comment on table public.song_title_cache is '曲名の日本語表記の問い合わせ結果。japanese が null は「見つからなかった」（Edge Function 専用）';

create table public.song_title_usage (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  count integer not null default 0 check (count >= 0),
  primary key (user_id, day)
);

create table public.song_title_daily_total (
  day date primary key,
  count integer not null default 0 check (count >= 0)
);

comment on table public.song_title_usage is '曲名の日本語表記（Gemini を呼んだ分）のユーザー別・日別回数（Edge Function 専用）';
comment on table public.song_title_daily_total is '曲名の日本語表記（Gemini を呼んだ分）の全ユーザー合計の日別回数（Edge Function 専用）';

-- ポリシーを作らないので、anon / authenticated からは読み書きできない
alter table public.song_title_cache enable row level security;
alter table public.song_title_usage enable row level security;
alter table public.song_title_daily_total enable row level security;

create function public.consume_song_title_quota(
  p_user_id uuid,
  p_user_limit integer,
  p_global_limit integer
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_day date := (now() at time zone 'Asia/Tokyo')::date;
  v_count integer;
begin
  insert into public.song_title_usage as u (user_id, day, count)
  values (p_user_id, v_day, 1)
  on conflict (user_id, day) do update
    set count = u.count + 1
    where u.count < p_user_limit
  returning u.count into v_count;
  if v_count is null then
    return 'user_limit';
  end if;

  v_count := null;
  insert into public.song_title_daily_total as t (day, count)
  values (v_day, 1)
  on conflict (day) do update
    set count = t.count + 1
    where t.count < p_global_limit
  returning t.count into v_count;
  if v_count is null then
    update public.song_title_usage
      set count = count - 1
      where user_id = p_user_id and day = v_day;
    return 'global_limit';
  end if;

  return 'ok';
end;
$$;

revoke all on function public.consume_song_title_quota(uuid, integer, integer) from public, anon, authenticated;
grant execute on function public.consume_song_title_quota(uuid, integer, integer) to service_role;

notify pgrst, 'reload schema';
