-- 会場検索（Google Places Autocomplete）は呼び出し単位で課金される。匿名アカウントは作り直せるため、
-- ユーザー別の上限だけでは 1 人で費用を使い切れてしまうので、全ユーザー合計の上限も数える。
-- 数えるのはキャッシュに当たらず Google を呼ぶ検索だけ。concert_discovery の上限と同じ作り。

create table public.venue_search_usage (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  count integer not null default 0 check (count >= 0),
  primary key (user_id, day)
);

comment on table public.venue_search_usage is '会場検索（Google を呼んだ分）のユーザー別・日別回数（Edge Function 専用）';

create table public.venue_search_daily_total (
  day date primary key,
  count integer not null default 0 check (count >= 0)
);

comment on table public.venue_search_daily_total is '会場検索（Google を呼んだ分）の全ユーザー合計の日別回数（Edge Function 専用）';

-- ポリシーを作らないので、anon / authenticated からは読み書きできない
alter table public.venue_search_usage enable row level security;
alter table public.venue_search_daily_total enable row level security;

-- ユーザー別と全体の両方が上限内なら両方を 1 増やして 'ok' を返す。
-- 超えていれば何も増やさず 'user_limit' か 'global_limit' を返す（1 つのトランザクションで数えるので同時に呼ばれても超えない）。
create function public.consume_venue_search_quota(
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
  insert into public.venue_search_usage as u (user_id, day, count)
  values (p_user_id, v_day, 1)
  on conflict (user_id, day) do update
    set count = u.count + 1
    where u.count < p_user_limit
  returning u.count into v_count;
  if v_count is null then
    return 'user_limit';
  end if;

  v_count := null;
  insert into public.venue_search_daily_total as t (day, count)
  values (v_day, 1)
  on conflict (day) do update
    set count = t.count + 1
    where t.count < p_global_limit
  returning t.count into v_count;
  if v_count is null then
    update public.venue_search_usage
      set count = count - 1
      where user_id = p_user_id and day = v_day;
    return 'global_limit';
  end if;

  return 'ok';
end;
$$;

revoke all on function public.consume_venue_search_quota(uuid, integer, integer) from public, anon, authenticated;
grant execute on function public.consume_venue_search_quota(uuid, integer, integer) to service_role;
