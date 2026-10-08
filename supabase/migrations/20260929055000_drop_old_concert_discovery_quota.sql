-- 全体の上限も数える consume_concert_discovery_quota(uuid, integer, integer) を使う Edge Function に
-- 切り替えたので、ユーザー別の上限だけの旧版を消す。
drop function if exists public.consume_concert_discovery_quota(uuid, integer);
