-- 匿名アカウントは作り直せるため、ユーザー別の上限だけでは 1 人で Gemini の無料枠（プロジェクト全体で 1 日 500 回）を
-- 使い切れてしまう。全ユーザー合計の上限も数える。

create table public.concert_discovery_daily_total (
  day date primary key,
  count integer not null default 0 check (count >= 0)
);

comment on table public.concert_discovery_daily_total is '今後の公演の検索（キャッシュ外）の全ユーザー合計の日別回数（Edge Function 専用）';

-- ポリシーを作らないので、anon / authenticated からは読み書きできない
alter table public.concert_discovery_daily_total enable row level security;

-- 旧版の (uuid, integer) は、新しい Edge Function をデプロイするまで旧版の関数が呼ぶので残す。
-- 削除は 20260929055000_drop_old_concert_discovery_quota.sql で行う。

-- ユーザー別と全体の両方が上限内なら両方を 1 増やして 'ok' を返す。
-- 超えていれば何も増やさず 'user_limit' か 'global_limit' を返す（1 つのトランザクションで数えるので同時に呼ばれても超えない）。
create function public.consume_concert_discovery_quota(
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
  insert into public.concert_discovery_usage as u (user_id, day, count)
  values (p_user_id, v_day, 1)
  on conflict (user_id, day) do update
    set count = u.count + 1
    where u.count < p_user_limit
  returning u.count into v_count;
  if v_count is null then
    return 'user_limit';
  end if;

  v_count := null;
  insert into public.concert_discovery_daily_total as t (day, count)
  values (v_day, 1)
  on conflict (day) do update
    set count = t.count + 1
    where t.count < p_global_limit
  returning t.count into v_count;
  if v_count is null then
    update public.concert_discovery_usage
      set count = count - 1
      where user_id = p_user_id and day = v_day;
    return 'global_limit';
  end if;

  return 'ok';
end;
$$;

revoke all on function public.consume_concert_discovery_quota(uuid, integer, integer) from public, anon, authenticated;
grant execute on function public.consume_concert_discovery_quota(uuid, integer, integer) to service_role;
